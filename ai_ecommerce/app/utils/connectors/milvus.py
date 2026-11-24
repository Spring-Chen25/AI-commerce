"""Milvus 连接器（向量数据库，pymilvus 同步 SDK 经 run_sync 限时执行）。

- 依赖：pymilvus==2.5.0（需 setuptools<81 提供 pkg_resources，见 requirements）。
- 未配置 MILVUS_HOST 时 enabled=False。
- 同步调用走 run_sync 硬超时；connect 传 timeout kwarg 给底层 gRPC 双保险。
- 提供 get_client()：返回 pymilvus 连接别名（默认 "default"）。
"""

from typing import Any

from app.config import settings
from app.utils.connectors.base import BaseConnector

ALIAS = "default"  # 连接别名，业务层按此引用


class MilvusConnector(BaseConnector):
    name = "milvus"

    @property
    def enabled(self) -> bool:
        return bool(settings.MILVUS_HOST)

    async def connect(self) -> Any:
        """延迟导入：建立 Milvus 连接（同步 SDK 放线程池）。"""
        from pymilvus import connections

        kwargs: dict[str, Any] = {
            "alias": ALIAS,
            "host": settings.MILVUS_HOST,
            "port": settings.MILVUS_PORT,
            "timeout": 5,  # 传给底层 gRPC 连接的建链超时
        }
        if settings.MILVUS_USER:
            kwargs["user"] = settings.MILVUS_USER
            kwargs["password"] = settings.MILVUS_PASSWORD
        await self.run_sync(connections.connect, **kwargs)
        return connections

    async def _do_close(self) -> None:
        await self.run_sync(self._client.disconnect, ALIAS)

    async def _do_health(self) -> bool:
        # 能取到 server version 视为存活（API 在 pymilvus.utility，非 connections）
        from pymilvus import utility

        return bool(await self.run_sync(
            utility.get_server_version, using=ALIAS, timeout=5
        ))

    def get_client(self) -> Any:
        return self.client

    def get_alias(self) -> str:
        return ALIAS


connector = MilvusConnector()
