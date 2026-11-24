"""MinIO 连接器（对象存储，S3 协议兼容；同步 SDK 经 run_sync 限时执行）。

- 依赖：minio（未安装时 connect() 才报错，可降级）。
- 连接时若 MINIO_BUCKET 不存在则自动创建（用户确认保持此行为）。
- 注入带超时的 urllib3 http_client（connect=3s / read=5s / 不重试），
  加 run_sync 硬超时双保险：服务不可达时限期降级，绝不拖垮启动。
- 提供 get_client() / get_bucket()。
"""

from typing import Any

from app.config import settings
from app.utils.connectors.base import BaseConnector


class MinIOConnector(BaseConnector):
    name = "minio"

    @property
    def enabled(self) -> bool:
        # 端点 / 密钥 / 桶齐全才启用
        return bool(
            settings.MINIO_ENDPOINT
            and settings.MINIO_ACCESS_KEY
            and settings.MINIO_SECRET_KEY
            and settings.MINIO_BUCKET
        )

    async def connect(self) -> Any:
        """延迟导入：创建带超时的 MinIO 客户端并确保桶存在。"""
        import urllib3
        from minio import Minio

        # socket 级超时：连接 3s、读取 5s、禁用重试，避免不可达时长久等待
        http_client = urllib3.PoolManager(
            timeout=urllib3.Timeout(connect=3.0, read=5.0),
            retries=urllib3.Retry(total=0, connect=0, read=0),
        )

        def _build():
            client = Minio(
                settings.MINIO_ENDPOINT,
                access_key=settings.MINIO_ACCESS_KEY,
                secret_key=settings.MINIO_SECRET_KEY,
                secure=settings.MINIO_SECURE,
                http_client=http_client,
            )
            if not client.bucket_exists(settings.MINIO_BUCKET):
                client.make_bucket(settings.MINIO_BUCKET)
            return client

        return await self.run_sync(_build)

    async def _do_close(self) -> None:
        # minio 客户端为无状态 HTTP 客户端，无需显式关闭
        return None

    async def _do_health(self) -> bool:
        return bool(await self.run_sync(
            lambda: self._client.bucket_exists(settings.MINIO_BUCKET)
        ))

    def get_client(self) -> Any:
        return self.client

    def get_bucket(self) -> str:
        return settings.MINIO_BUCKET


connector = MinIOConnector()
