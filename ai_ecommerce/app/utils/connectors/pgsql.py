"""PostgreSQL 连接器（异步，SQLAlchemy async engine + asyncpg）。

- 依赖：sqlalchemy[asyncio]、asyncpg（未安装时 connect() 才报错，可降级）。
- 提供 create_session()：异步 session 上下文，供业务层使用。
- 注意：与 MySQL 各自独立 engine，禁止同一套 DAO 混用。
"""

import asyncio
from typing import Any

from app.config import settings
from app.utils.connectors.base import BaseConnector

CONNECT_TIMEOUT = 8.0  # 异步探活硬超时（async 调用可被安全取消）


class PgSQLConnector(BaseConnector):
    name = "pgsql"

    @property
    def enabled(self) -> bool:
        return bool(settings.POSTGRES_URL)

    async def connect(self) -> Any:
        """延迟导入：创建异步 engine（驱动 asyncpg），全程可 await。"""
        from sqlalchemy import text
        from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

        url = settings.POSTGRES_URL
        if not url.startswith("postgresql+"):
            url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
        engine = create_async_engine(
            url, pool_pre_ping=True, echo=False,
            connect_args={"timeout": 5},  # asyncpg 建链超时
        )
        maker = async_sessionmaker(engine, expire_on_commit=False)
        # 立即验证连通性（异步 + 硬超时，避免不可达时长久等待）
        async with engine.connect() as conn:
            await asyncio.wait_for(conn.execute(text("SELECT 1")), timeout=CONNECT_TIMEOUT)
        # engine + sessionmaker 一起存，便于 get_session
        return {"engine": engine, "sessionmaker": maker}

    async def _do_close(self) -> None:
        await self._client["engine"].dispose()

    async def _do_health(self) -> bool:
        from sqlalchemy import text

        async with self._client["engine"].connect() as conn:
            result = await asyncio.wait_for(
                conn.execute(text("SELECT 1")), timeout=CONNECT_TIMEOUT
            )
            return result.scalar() == 1

    def create_session(self) -> Any:
        """返回一个异步 session（用法：async with connector.create_session() as s: ...）。"""
        return self.client["sessionmaker"]()


connector = PgSQLConnector()
