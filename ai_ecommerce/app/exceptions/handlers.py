"""全局异常捕获：把所有异常统一转成 ResponseModel 结构，不向客户端暴露堆栈。

在 main.py 通过 register_exception_handlers(app) 一次性注册。
"""

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import OperationalError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.exceptions.base import AppException
from app.schemas.common import ResponseModel

logger = logging.getLogger(__name__)


def _response(
    code: int,
    message: str,
    data: Any = None,
    http_status: int = 200,
) -> JSONResponse:
    """构造统一响应体。"""
    payload = ResponseModel(code=code, message=message, data=data).model_dump()
    return JSONResponse(status_code=http_status, content=payload)


def register_exception_handlers(app: FastAPI) -> None:
    """注册全部异常处理器（业务 / 校验 / HTTP / 兜底）。"""

    @app.exception_handler(AppException)
    async def app_exception_handler(request: Request, exc: AppException) -> JSONResponse:
        """业务异常：按异常自带 code/status 返回，warn 级日志。"""
        logger.warning(
            "biz_error path=%s code=%s msg=%s",
            request.url.path,
            exc.code,
            exc.message,
        )
        return _response(exc.code, exc.message, exc.data, exc.http_status)

    @app.exception_handler(RequestValidationError)
    async def validation_handler(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        """入参校验失败：code=422，携带字段级错误明细。"""
        errors = exc.errors()
        logger.warning("validation_error path=%s errors=%s", request.url.path, errors)
        return _response(422, "参数校验失败", errors, 422)

    @app.exception_handler(StarletteHTTPException)
    async def http_exception_handler(
        request: Request, exc: StarletteHTTPException
    ) -> JSONResponse:
        """原生 HTTPException（404/405 等）：纳入统一响应体，避免裸 detail。"""
        status = exc.status_code
        logger.warning("http_error path=%s status=%s detail=%s", request.url.path, status, exc.detail)
        return _response(status, str(exc.detail), None, status)

    @app.exception_handler(OperationalError)
    async def database_unavailable_handler(request: Request, exc: OperationalError) -> JSONResponse:
        """数据库连接失败时返回可处理的 503，避免开发模式向前端输出堆栈。"""
        logger.error("database_unavailable path=%s error=%s", request.url.path, type(exc).__name__)
        return _response(503, "数据库暂不可用，请检查当前数据库连接和库是否存在", None, 503)

    @app.exception_handler(Exception)
    async def unhandled_handler(request: Request, exc: Exception) -> JSONResponse:
        """兜底：未知异常记录完整堆栈，客户端只收到 500 通用文案。"""
        logger.exception("unhandled_error path=%s", request.url.path)
        return _response(500, "服务内部错误", None, 500)
