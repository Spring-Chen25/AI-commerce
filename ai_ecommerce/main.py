"""应用入口：uvicorn main:app --reload

职责精简为四件事：
- 生命周期：统一初始化 / 释放外部连接器；
- 中间件：CORS、幂等、审计、访问日志（含 request-id）；
- 全局异常：统一注册；
- 路由注册：委托 app.routers.register_routes，本文件不感知具体路由。
"""

import json
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncIterator

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import settings
from app.exceptions.handlers import register_exception_handlers
from app.routers import register_routes
from app.utils.audit import AuditMiddleware
from app.utils.connectors import close_all, init_all
from app.utils.idempotency import IdempotencyMiddleware
from app.utils.logging import get_logger, setup_logging

setup_logging()
logger = get_logger("app")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """启动：并发初始化外部连接器；关闭：并发释放。未配置/未装包自动降级，不阻塞。"""
    conn_status = await init_all()
    logger.info("startup_complete connectors=%s", conn_status)
    yield
    await close_all()
    logger.info("shutdown_complete")


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    debug=settings.DEBUG,
    lifespan=lifespan,
)

# --- 中间件（FastAPI 后注册的先执行：审计 → 幂等 → CORS）---
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(IdempotencyMiddleware)
app.add_middleware(AuditMiddleware)


@app.middleware("http")
async def access_log(request: Request, call_next):
    """结构化访问日志 + request-id，并为 /api/v1 响应加统一信封标识头。"""
    request_id = request.headers.get("x-request-id", str(uuid.uuid4()))
    request.state.request_id = request_id
    started = time.perf_counter()
    response = await call_next(request)
    cost_ms = round((time.perf_counter() - started) * 1000, 2)
    response.headers["X-Request-ID"] = request_id
    if request.url.path.startswith("/api/v1"):
        response.headers["X-Api-Envelope"] = "1"  # 响应体遵循 ResponseModel 统一信封
    logger.info(
        json.dumps(
            {
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "cost_ms": cost_ms,
            },
            ensure_ascii=False,
        )
    )
    return response


# --- 全局异常处理 + 路由注册（均集中委托，本文件保持精简）---
register_exception_handlers(app)
register_routes(app, api_prefix="/api/v1")

# --- 静态资源 ---
app.mount("/static", StaticFiles(directory=Path(__file__).parent / "static"), name="static")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=settings.HOST,
        port=settings.PORT,
        reload=settings.DEBUG,
    )
