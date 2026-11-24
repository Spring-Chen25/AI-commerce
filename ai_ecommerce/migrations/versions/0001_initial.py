"""初始迁移：建立 audit_log 审计表

Revision ID: 0001_initial
Revises:
Create Date: 2026-11-20

后续业务表请用 `alembic revision --autogenerate -m "xxx"` 生成，并挂在本人本迁移之后。
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# Alembic 标识
revision: str = "0001_initial"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """建表：字段与 app/models/audit.py 保持一致。"""
    op.create_table(
        "audit_log",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("request_id", sa.String(64), nullable=True),
        sa.Column("method", sa.String(16), nullable=False),
        sa.Column("path", sa.String(512), nullable=False),
        sa.Column("client_ip", sa.String(64), nullable=True),
        sa.Column("user", sa.String(128), nullable=True),
        sa.Column("status", sa.Integer(), nullable=False),
        sa.Column("cost_ms", sa.Float(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_audit_log_request_id", "audit_log", ["request_id"])


def downgrade() -> None:
    """回滚：删索引与表。"""
    op.drop_index("ix_audit_log_request_id", table_name="audit_log")
    op.drop_table("audit_log")
