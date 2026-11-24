"""集中式配置：全部来自环境变量（.env），启动时实例化即校验。

约定：连接类配置留空表示"未启用"，连接器 health() 返回 disabled，不阻塞启动。
"""

from functools import lru_cache
from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # --- 应用 ---
    APP_NAME: str = "ai_ecommerce"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = True
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    # 控制这个行为的白名单——它规定,"允许哪些前端域名跨域调用本后端接口"。
    CORS_ORIGINS: str = "http://localhost:3000,http://localhost:5173"

    # --- ORM 默认库（同步引擎：postgresql+psycopg:// / mysql+pymysql:// / sqlite）---
    DATABASE_URL: str = "sqlite:///./ai_ecommerce.db"

    # --- 外部连接（留空 = 未启用）---
    MYSQL_URL: str = ""  # mysql+pymysql://user:pwd@host:3306/db?charset=utf8mb4（密码 @ 需编码为 %40）
    POSTGRES_URL: str = ""  # postgresql+asyncpg://user:pwd@host:5432/db（连接器用异步驱动）
    REDIS_URL: str = ""  # redis://:pwd@host:6379/0
    MINIO_ENDPOINT: str = ""  # host:9000
    MINIO_ACCESS_KEY: str = ""
    MINIO_SECRET_KEY: str = ""
    MINIO_BUCKET: str = ""
    MINIO_SECURE: bool = False
    MILVUS_HOST: str = ""
    MILVUS_PORT: int = 19530
    MILVUS_USER: str = ""
    MILVUS_PASSWORD: str = ""

    # --- Celery（broker/backend 走 Redis；留空 = 未启用）---
    # 假设：复用上面 Redis，broker 用 db/1、backend 用 db/2，与缓存 db/0 隔离
    CELERY_BROKER_URL: str = ""
    CELERY_RESULT_BACKEND: str = ""

    # --- 日志 ---
    LOG_LEVEL: str = "INFO"
    LOG_DIR: str = "logs"
    LOG_MAX_BYTES: int = 10 * 1024 * 1024  # 单文件 10MB
    LOG_BACKUP_COUNT: int = 7

    # --- JWT（骨架，路由按需使用；生产用环境变量注入强密钥）---
    JWT_SECRET_KEY: str = "change-me-in-env"
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 60

    # 平台凭据字段使用 Fernet 加密后再写库；生产环境必须单独配置强密钥。
    CREDENTIAL_ENCRYPTION_KEY: str = ""

    @property
    def cors_origins_list(self) -> List[str]:
        raw = self.CORS_ORIGINS.strip()
        if raw == "*":
            return ["*"]
        return [item.strip() for item in raw.split(",") if item.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
