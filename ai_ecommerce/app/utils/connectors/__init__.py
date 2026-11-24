"""外部连接层：MySQL / PostgreSQL / Redis / MinIO / Milvus / Celery 的统一入口。

设计约定：
- 每个连接器懒加载单例，第三方包延迟到 connect() 才导入（未安装不报错）。
- 全异步生命周期：init_all() / close_all() / health_all() 均为 async。
- 未配置或连接失败时 health() 返回 disabled/error，不抛异常、不阻塞应用启动。
- 生命周期由 main.py 的 lifespan 统一 await init_all() / await close_all()。
"""

from app.utils.connectors.base import BaseConnector, registry
from app.utils.connectors import (
    mysql,
    pgsql,
    redis,
    minio,
    milvus,
    celery,
)

# 注册所有连接器（顺序：关系库 → 缓存 → 对象存储 → 向量库 → 任务队列）
registry.register(mysql.connector)
registry.register(pgsql.connector)
registry.register(redis.connector)
registry.register(minio.connector)
registry.register(milvus.connector)
registry.register(celery.connector)


async def init_all() -> dict:
    """启动时并发连接；返回 {name: health} 供日志与 /ready 使用。"""
    return await registry.init_all()


async def close_all() -> None:
    """关闭时并发释放连接。"""
    await registry.close_all()


async def health_all() -> dict:
    """并发返回所有连接器健康状态（供 /ready 探测）。"""
    return await registry.health_all()


def get(name: str) -> BaseConnector:
    """按名取连接器实例（未注册抛 ConnectionException）。"""
    return registry.get(name)


__all__ = [
    "BaseConnector",
    "registry",
    "init_all",
    "close_all",
    "health_all",
    "get",
    "mysql",
    "pgsql",
    "redis",
    "minio",
    "milvus",
    "celery",
]
