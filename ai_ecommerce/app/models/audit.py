"""审计日志 ORM 模型：记录写操作事件（供 AuditMiddleware 落库）。

- 绑定默认库（settings.DATABASE_URL）；如需分库，让本模型继承 BindKeyMixin 并声明 __bind_key__。
- 字段与 audit.py 的 event 字典一一对应。
"""

from datetime import datetime

from sqlalchemy import DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class AuditLog(Base):
    """审计事件表。"""

    __tablename__ = "audit_log"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    request_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    method: Mapped[str] = mapped_column(String(16), nullable=False)
    path: Mapped[str] = mapped_column(String(512), nullable=False)
    client_ip: Mapped[str | None] = mapped_column(String(64), nullable=True)
    user: Mapped[str | None] = mapped_column(String(128), nullable=True)
    status: Mapped[int] = mapped_column(Integer, nullable=False)
    cost_ms: Mapped[float | None] = mapped_column(nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, server_default=func.now()
    )
