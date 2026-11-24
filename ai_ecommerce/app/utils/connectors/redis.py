"""Redis 连接器（异步，redis.asyncio 连接池）。

- 依赖：redis（未安装时 connect() 才报错，可降级）。
- 提供 get_client()：返回 Redis 客户端，供缓存 / 幂等 / 限流复用。
"""

import asyncio
from typing import Any

from app.config import settings
from app.utils.connectors.base import BaseConnector

CONNECT_TIMEOUT = 5.0  # 异步探活硬超时（async 调用可被安全取消）


class RedisConnector(BaseConnector):
    name = "redis"

    @property
    def enabled(self) -> bool:
        return bool(settings.REDIS_URL)

    async def connect(self) -> Any:
        """延迟导入：创建异步 Redis 客户端（内部自带连接池）并验证连通。"""
        import redis.asyncio as aioredis

        client = aioredis.from_url(
            settings.REDIS_URL, decode_responses=True,
            socket_connect_timeout=3, socket_timeout=5,
        )
        await asyncio.wait_for(client.ping(), timeout=CONNECT_TIMEOUT)
        return client

    async def _do_close(self) -> None:
        await self._client.aclose()

    async def _do_health(self) -> bool:
        return bool(await asyncio.wait_for(self._client.ping(), timeout=CONNECT_TIMEOUT))

    def get_client(self) -> Any:
        """获取 Redis 客户端；未连接时抛 ConnectionException。"""
        return self.client


connector = RedisConnector()
