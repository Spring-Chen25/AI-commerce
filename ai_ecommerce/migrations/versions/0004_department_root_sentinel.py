"""部门根节点使用 parent_id=0，部门 ID 保持从 1 开始。

Revision ID: 0004_department_root_sentinel
Revises: 0003_permission_description
Create Date: 2026-11-23
"""

from alembic import op
import sqlalchemy as sa


revision = "0004_department_root_sentinel"
down_revision = "0003_permission_description"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """移除无法表达根节点 0 的自关联外键，改由服务层保证同租户父部门有效。"""
    op.drop_constraint("biz_department_parent_id_fkey", "biz_department", type_="foreignkey")
    op.execute("UPDATE biz_department SET parent_id = 0 WHERE parent_id IS NULL")
    op.alter_column("biz_department", "parent_id", existing_type=sa.Integer(), nullable=False, server_default="0")
    op.create_check_constraint("ck_department_parent_id_nonnegative", "biz_department", "parent_id >= 0")


def downgrade() -> None:
    """回滚时把根节点哨兵值还原为 NULL，再恢复自关联外键。"""
    op.drop_constraint("ck_department_parent_id_nonnegative", "biz_department", type_="check")
    op.execute("UPDATE biz_department SET parent_id = NULL WHERE parent_id = 0")
    op.alter_column("biz_department", "parent_id", existing_type=sa.Integer(), nullable=True, server_default=None)
    op.create_foreign_key("biz_department_parent_id_fkey", "biz_department", "biz_department", ["parent_id"], ["id"])
