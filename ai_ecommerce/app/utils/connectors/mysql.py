"""MySQL 连接器（同步驱动 PyMySQL / SQLAlchemy engine，经 run_sync 限时执行）。

- 依赖：pymysql（已在 requirements）；SQLAlchemy engine 供 ORM/原生 SQL 复用。
- 未配置 MYSQL_URL 时 enabled=False，不连接。
- 同步调用统一走 run_sync 硬超时，服务不可达时限期降级不阻塞启动。
"""

from typing import Any

from app.config import settings
from app.utils.connectors.base import BaseConnector


class MySQLConnector(BaseConnector):
    name = "mysql"

    @property
    def enabled(self) -> bool:
        return bool(settings.MYSQL_URL)

    async def connect(self) -> Any:
        """延迟导入：建立 SQLAlchemy 同步 engine（驱动 pymysql）；同步操作放线程池。"""
        from sqlalchemy import create_engine

        url = settings.MYSQL_URL
        # 仅在未显式指定驱动时才补 +pymysql，避免把 mysql+pymysql:// 误伤成 mysql+pymysql+pymysql://
        if url.startswith("mysql://"):
            url = url.replace("mysql://", "mysql+pymysql://", 1)

        def _build():
            engine = create_engine(
                url, pool_pre_ping=True, echo=False,
                connect_args={"connect_timeout": 5},  # pymysql 连接超时
            )
            with engine.connect() as conn:  # 立即验证连通性
                conn.exec_driver_sql("SELECT 1")
            return engine

        return await self.run_sync(_build)

    async def _do_close(self) -> None:
        await self.run_sync(self._client.dispose)

    async def _do_health(self) -> bool:
        def _ping() -> bool:
            with self._client.connect() as conn:
                return conn.exec_driver_sql("SELECT 1").scalar() == 1

        return await self.run_sync(_ping)

    def get_engine(self) -> Any:
        """获取底层 engine（供 DAO 绑定 session 使用）。"""
        return self.client


connector = MySQLConnector()
