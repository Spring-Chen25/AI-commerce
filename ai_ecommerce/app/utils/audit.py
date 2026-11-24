"""审计中间件：记录写操作到日志 + 落库（audit_log 表）。

- 记录要素：request_id、方法、路径、客户端 IP、用户（若已鉴权）、状态码、耗时。
- 只审计写方法（POST/PUT/PATCH/DELETE）。
- 落库走默认库（settings.DATABASE_URL）的同步会话，用 asyncio.to_thread 包装避免阻塞事件循环。
- 落库失败只记日志、绝不影响业务主流程；未配数据库 / 表不存在时自动降级为仅日志。
"""

import asyncio
import json
import time
from typing import Any, Dict

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

from app.utils.logging import get_logger

logger = get_logger("audit")
_AUDIT_METHODS = {"POST", "PUT", "PATCH", "DELETE"}


class AuditMiddleware(BaseHTTPMiddleware):
    """审计中间件：写操作落结构化日志 + 落库。"""

    async def dispatch(self, request: Request, call_next) -> Response:
        if request.method not in _AUDIT_METHODS:
            return await call_next(request)

        started = time.perf_counter()
        response = await call_next(request)
        cost_ms = round((time.perf_counter() - started) * 1000, 2)

        event: Dict[str, Any] = {
            "request_id": getattr(request.state, "request_id", None),
            "method": request.method,
            "path": request.url.path,
            "client_ip": request.client.host if request.client else None,
            "user": getattr(request.state, "user_id", None),
            "status": response.status_code,
            "cost_ms": cost_ms,
        }
        logger.info("audit %s", json.dumps(event, ensure_ascii=False))

        # 落库：同步会话放线程池，失败由 write_to_db 内部吞掉，不影响响应
        await write_to_db(event)
        return response


async def write_to_db(event: Dict[str, Any]) -> None:
    """把审计事件写入 audit_log 表（异步包装同步会话）。

    设计约束：
    - 用 asyncio.to_thread 执行同步 DB 操作，避免阻塞事件循环；
    - 任何异常（未装驱动 / 未配库 / 表不存在）只记 debug 日志并吞掉，
      绝不因审计失败影响业务主流程——这与"优雅降级"基座原则一致。
    """
    try:
        await asyncio.to_thread(_insert, event)
    except Exception as exc:  # 审计失败不影响主流程
        logger.debug("audit db write skipped: %s", exc)


def _insert(event: Dict[str, Any]) -> None:
    """同步写入：独立会话，用后即关。"""
    from app.database import get_session
    from app.models.audit import AuditLog

    with get_session() as db:
        db.add(
            AuditLog(
                request_id=event.get("request_id"),
                method=event.get("method"),
                path=event.get("path"),
                client_ip=event.get("client_ip"),
                user=event.get("user"),
                status=event.get("status"),
                cost_ms=event.get("cost_ms"),
            )
        )
        db.commit()
