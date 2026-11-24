"""幂等中间件：基于请求头 Idempotency-Key 防重复提交。

- 存储优先用 Redis（多实例 / 重启不丢）；Redis 未连接时自动降级为内存字典（单进程）。
- 仅对配置的方法生效（默认 POST）；重复 key 直接回放首次响应。
- TTL 到期后自动失效；未带 key 的请求直接放行。
- 存储读写失败一律视为未命中 / 不缓存，绝不影响业务主流程。
"""

import base64
import json
import time
from typing import Any, Dict, Optional, Tuple

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.utils.connectors import get as get_connector
from app.utils.logging import get_logger

logger = get_logger("idempotency")

_METHODS = {"POST"}
_TTL_SECONDS = 10 * 60
_HEADER = "Idempotency-Key"
_KEY_PREFIX = "idem:"  # Redis key 前缀，便于隔离与排查

# 内存降级存储：key -> (过期时间戳, status_code, body, headers)
_mem_store: Dict[str, Tuple[float, int, bytes, dict]] = {}

# 缓存记录结构（Redis 与内存共用）：(status, body, headers)
Cached = Tuple[int, bytes, dict]


class IdempotencyMiddleware(BaseHTTPMiddleware):
    """幂等中间件：同 key 的重复请求回放首次响应。"""

    async def dispatch(self, request: Request, call_next) -> Response:
        key = request.headers.get(_HEADER)
        if not key or request.method not in _METHODS:
            return await call_next(request)  # 未带 key / 非目标方法：放行

        redis = self._redis()
        cache_key = _KEY_PREFIX + key

        cached = await self._load(redis, cache_key)
        if cached is not None:  # 命中：回放首次响应
            status, body, headers = cached
            return Response(content=body, status_code=status, headers=headers)

        response = await call_next(request)  # 首次：执行并缓存响应体
        body = b"".join([chunk async for chunk in response.body_iterator])
        headers = dict(response.headers)
        await self._save(redis, cache_key, response.status_code, body, headers)
        return Response(content=body, status_code=response.status_code, headers=headers)

    # --- 存储后端：Redis 优先，未连接则降级内存 ---
    @staticmethod
    def _redis() -> Any | None:
        """返回已连接的 Redis 客户端；未连接 / 未装包 / 未注册时返回 None。"""
        try:
            conn = get_connector("redis")
            return conn.client if conn.is_connected else None
        except Exception:
            return None

    @staticmethod
    async def _load(redis: Any | None, cache_key: str) -> Optional[Cached]:
        """读取缓存；任何异常视为未命中。"""
        try:
            if redis is not None:
                raw = await redis.get(cache_key)
                if not raw:
                    return None
                data = json.loads(raw)
                return data["status"], base64.b64decode(data["body"]), data["headers"]
            item = _mem_store.get(cache_key)
            if not item or item[0] <= time.time():
                return None
            _, status, body, headers = item
            return status, body, headers
        except Exception:
            return None

    @staticmethod
    async def _save(
        redis: Any | None, cache_key: str, status: int, body: bytes, headers: dict
    ) -> None:
        """写入缓存；失败只记日志，不影响主流程。"""
        try:
            if redis is not None:
                data = {
                    "status": status,
                    "body": base64.b64encode(body).decode("ascii"),
                    "headers": headers,
                }
                await redis.setex(cache_key, _TTL_SECONDS, json.dumps(data, ensure_ascii=False))
            else:
                _mem_store[cache_key] = (time.time() + _TTL_SECONDS, status, body, headers)
        except Exception as exc:
            logger.warning("idempotency save failed key=%s err=%s", cache_key, exc)


def clear_store() -> None:
    """清空内存存储（测试用）；Redis 侧按前缀清理需业务自行实现。"""
    _mem_store.clear()
