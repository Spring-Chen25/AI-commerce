"""路由层：对外提供统一的路由注册入口，保持 main.py 精简。

新增业务路由只需两步：
1. 在此 import 对应模块的 router；
2. 在 register_routes() 内 app.include_router(...)。
新增路由一律挂 api_prefix（默认 /api/v1）；health 探针挂根路径便于直连。
"""

from fastapi import FastAPI

from app.routers import health, rbac

__all__ = ["register_routes"]


def register_routes(app: FastAPI, api_prefix: str = "/api/v1") -> None:
    """统一注册全部路由：探针挂根路径，业务路由挂 api_prefix。"""
    app.include_router(health.router)  # /health、/ready
    app.include_router(rbac.router, prefix=api_prefix)
    # 新增业务路由示例（取消注释并替换）：
    # from app.routers import xxx
    # app.include_router(xxx.router, prefix=api_prefix)
