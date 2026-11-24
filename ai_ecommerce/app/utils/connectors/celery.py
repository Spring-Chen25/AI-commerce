"""Celery 连接器（异步任务队列，broker/backend 走 Redis；同步 SDK 经 run_sync 限时执行）。

- 依赖：celery[redis]、kombu（已在 requirements）。
- 未配置 CELERY_BROKER_URL 时 enabled=False，不创建 app。
- broker 探活用 kombu ensure_connection(timeout=3) + run_sync 硬超时双保险。
- 提供 get_app()：业务模块用它声明 @app.task / 投递任务。
"""

from typing import Any

from app.config import settings
from app.utils.connectors.base import BaseConnector


class CeleryConnector(BaseConnector):
    name = "celery"

    @property
    def enabled(self) -> bool:
        return bool(settings.CELERY_BROKER_URL)

    async def connect(self) -> Any:
        """延迟导入：创建 Celery app 并验证 broker 可达（同步探活放线程池）。"""
        from celery import Celery

        app = Celery(
            settings.APP_NAME,
            broker=settings.CELERY_BROKER_URL,
            backend=settings.CELERY_RESULT_BACKEND or None,
        )
        app.conf.update(
            task_serializer="json",
            result_serializer="json",
            accept_content=["json"],
            timezone="Asia/Shanghai",
            enable_utc=True,
            task_track_started=True,
        )

        def _check_broker():
            with app.connection_for_read() as conn:
                conn.ensure_connection(max_retries=0, timeout=3)

        await self.run_sync(_check_broker)
        return app

    async def _do_close(self) -> None:
        # Celery app 连接池由 kombu 自行管理，关闭由 worker 负责；此处无需显式释放。
        return None

    async def _do_health(self) -> bool:
        def _ping() -> bool:
            with self._client.connection_for_read() as conn:
                conn.ensure_connection(max_retries=0, timeout=3)
                return True

        try:
            return await self.run_sync(_ping)
        except Exception:
            return False

    def get_app(self) -> Any:
        """获取 Celery app 实例；未配置时抛 ConnectionException。"""
        return self.client


connector = CeleryConnector()
