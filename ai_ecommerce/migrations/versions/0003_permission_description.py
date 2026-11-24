"""为权限目录增加业务说明字段。

Revision ID: 0003_permission_description
Revises: 0002_rbac_multitenancy
Create Date: 2026-11-23
"""

from alembic import op
import sqlalchemy as sa


revision = "0003_permission_description"
down_revision = "0002_rbac_multitenancy"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """保存《项目权限表》中的业务说明，供后台和接口展示。"""
    op.add_column("sys_permission", sa.Column("description", sa.String(512), nullable=True))


def downgrade() -> None:
    """回滚权限业务说明字段。"""
    op.drop_column("sys_permission", "description")
