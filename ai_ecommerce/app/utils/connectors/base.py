"""连接器基类与注册表：统一异步生命周期与健康检查契约。

设计约定（全异步）：
- connect()/close()/health() 均为 async，在事件循环中安全执行。
- 异步驱动（asyncpg / redis.asyncio）直接 await；同步驱动（PyMySQL/MinIO/Milvus）
  在各连接器内部用 asyncio.to_thread 包装，避免阻塞事件循环。
- 未配置或连接失败只记录、不抛出，始终不阻塞应用启动。
"""

import asyncio
import functools
import logging
import queue
import threading
from abc import ABC, abstractmethod
from typing import Any, Callable, Dict

logger = logging.getLogger(__name__)

# 同步 SDK 调用的硬超时（秒）。守护线程执行，超时即降级，不阻塞启动与关闭。
SYNC_CALL_TIMEOUT = 8.0


def _run_sync_bounded(fn: Callable, *args: Any, timeout: float = SYNC_CALL_TIMEOUT, **kwargs: Any) -> Any:
    """在守护线程里执行同步调用并施加硬超时。

    为何不用 asyncio.to_thread + wait_for：wait_for 超时后事件循环关闭仍会等待
    线程池里的残留线程，导致进程卡死。改用 daemon 线程 + queue：超时后立即
    放弃等待（线程随解释器退出被回收），调用方按时收到 TimeoutError 并降级。

    返回 fn 的结果；超时抛 TimeoutError；fn 内部异常原样抛出。
    """
    result: "queue.Queue[tuple]" = queue.Queue(maxsize=1)

    def worker() -> None:
        try:
            result.put((True, fn(*args, **kwargs)))
        except Exception as exc:  # 把同步异常带回调用方
            result.put((False, exc))

    threading.Thread(target=worker, daemon=True).start()
    try:
        ok, value = result.get(timeout=timeout)
    except queue.Empty:
        raise TimeoutError(f"同步调用超时（>{timeout}s）: {getattr(fn, '__name__', fn)}")
    if not ok:
        raise value
    return value


class BaseConnector(ABC):
    """连接器抽象基类（异步生命周期）。

    - name：注册名（唯一）
    - connect()：建立连接并返回客户端；第三方包在此延迟导入
    - close()：释放连接
    - health()：返回健康状态字典，任何情况都不抛异常
    - is_connected：底层客户端是否就绪（其它模块据此判断能否取用）
    - enabled：配置是否齐全（未配置则跳过连接）
    """

    name: str = "base"

    def __init__(self) -> None:
        self._client: Any = None
        self._error: str | None = None

    @property
    @abstractmethod
    def enabled(self) -> bool:
        """配置是否齐全；False 时注册表跳过连接。"""
        raise NotImplementedError

    @abstractmethod
    async def connect(self) -> Any:
        """建立并返回客户端（async）；第三方库在此方法内延迟导入。"""
        raise NotImplementedError

    @abstractmethod
    async def _do_close(self) -> None:
        """释放底层连接资源（async）。"""
        raise NotImplementedError

    @abstractmethod
    async def _do_health(self) -> bool:
        """返回底层连接是否存活（async 探活，如 ping）。"""
        raise NotImplementedError

    async def init(self) -> None:
        """统一初始化入口：未配置或失败只记录、不抛出。"""
        if not self.enabled:
            logger.info("connector[%s] disabled (未配置)", self.name)
            return
        try:
            self._client = await self.connect()
            self._error = None
            logger.info("connector[%s] connected", self.name)
        except Exception as exc:  # 未安装依赖 / 网络不通等，降级不阻塞启动
            self._client = None
            self._error = f"{type(exc).__name__}: {exc}"
            logger.warning("connector[%s] init failed: %s", self.name, self._error)

    async def close(self) -> None:
        """统一关闭入口。"""
        if self._client is None:
            return
        try:
            await self._do_close()
            logger.info("connector[%s] closed", self.name)
        except Exception as exc:
            logger.warning("connector[%s] close failed: %s", self.name, exc)
        finally:
            self._client = None

    async def health(self) -> Dict[str, Any]:
        """统一健康状态：disabled / ok / error，绝不抛异常。"""
        if not self.enabled:
            return {"status": "disabled"}
        if self._client is None:
            return {"status": "error", "error": self._error or "not connected"}
        try:
            alive = await self._do_health()
            return {"status": "ok" if alive else "error"}
        except Exception as exc:
            return {"status": "error", "error": str(exc)}

    @property
    def is_connected(self) -> bool:
        """底层客户端是否就绪（供幂等/审计等模块安全判断能否取用）。"""
        return self._client is not None

    @property
    def client(self) -> Any:
        """暴露底层客户端；未连接时抛 ConnectionException。"""
        from app.exceptions import ConnectionException

        if self._client is None:
            raise ConnectionException(f"连接器 {self.name} 未连接：{self._error or '未初始化'}")
        return self._client

    @staticmethod
    async def run_sync(fn: Callable, *args: Any, **kwargs: Any) -> Any:
        """异步封装同步 SDK 调用：丢进 executor 且不阻塞事件循环，带硬超时。

        子类所有同步驱动（PyMySQL / MinIO / pymilvus / kombu）的 connect/close/health
        都走这里，确保服务不可达时限期降级，不拖垮启动与 /ready。

        用 functools.partial 把 fn 及其 kwargs 绑定成单一可调用对象，因为
        run_in_executor(executor, func, *args) 不接受 func 自身的关键字参数。
        """
        bounded = functools.partial(_run_sync_bounded, fn, *args, **kwargs)
        return await asyncio.get_running_loop().run_in_executor(None, bounded)


class ConnectorRegistry:
    """连接器注册表：集中管理 init / close / health（全 async）。"""

    def __init__(self) -> None:
        self._connectors: Dict[str, BaseConnector] = {}

    def register(self, connector: BaseConnector) -> None:
        self._connectors[connector.name] = connector

    def get(self, name: str) -> BaseConnector:
        try:
            return self._connectors[name]
        except KeyError:
            from app.exceptions import ConnectionException

            raise ConnectionException(f"连接器未注册: {name}")

    async def init_all(self) -> dict:
        """启动时逐个连接（并发）；返回 {name: health} 供日志与 /ready 使用。

        gather 带总超时兜底：即便某连接器内部超时机制失效，也不会拖垮启动。
        """
        try:
            await asyncio.wait_for(
                asyncio.gather(*(c.init() for c in self._connectors.values())),
                timeout=SYNC_CALL_TIMEOUT + 4,
            )
        except asyncio.TimeoutError:
            logger.error("init_all 总超时：部分连接器初始化超时，已继续启动")
        return await self.health_all()

    async def close_all(self) -> None:
        """关闭时逐个释放连接（并发，带总超时兜底）。"""
        try:
            await asyncio.wait_for(
                asyncio.gather(*(c.close() for c in self._connectors.values())),
                timeout=SYNC_CALL_TIMEOUT + 4,
            )
        except asyncio.TimeoutError:
            logger.warning("close_all 总超时：部分连接器释放超时")

    async def health_all(self) -> dict:
        """并发返回所有连接器健康状态（供 /ready 探测，避免逐个串行等待）。"""
        try:
            results = await asyncio.wait_for(
                asyncio.gather(*(c.health() for c in self._connectors.values())),
                timeout=SYNC_CALL_TIMEOUT + 4,
            )
        except asyncio.TimeoutError:
            # 整体超时：直接返回静态 error 状态，绝不重复调用可能卡住的方法
            logger.error("health_all 总超时：返回降级状态")
            return {
                name: {"status": "error", "error": "health check timeout"}
                for name in self._connectors
            }
        return dict(zip(self._connectors.keys(), results))


registry = ConnectorRegistry()
