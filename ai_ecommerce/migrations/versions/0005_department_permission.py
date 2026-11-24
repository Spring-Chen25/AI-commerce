"""保存部门权限配置，但不改变用户角色授权。

Revision ID: 0005_department_permission
Revises: 0004_department_root_sentinel
Create Date: 2026-11-23
"""

from alembic import op
import sqlalchemy as sa


revision = "0005_department_permission"
down_revision = "0004_department_root_sentinel"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "sys_department_permission",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("tenant_id", sa.Integer(), sa.ForeignKey("sys_tenant.id"), nullable=False),
        sa.Column("dept_id", sa.Integer(), sa.ForeignKey("biz_department.id", ondelete="CASCADE"), nullable=False),
        sa.Column("perm_id", sa.Integer(), sa.ForeignKey("sys_permission.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("created_by", sa.Integer()),
        sa.Column("updated_by", sa.Integer()),
        sa.Column("deleted", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.UniqueConstraint("tenant_id", "dept_id", "perm_id", name="uq_department_permission"),
    )
    op.create_index("ix_sys_department_permission_tenant_id", "sys_department_permission", ["tenant_id"])


def downgrade() -> None:
    op.drop_index("ix_sys_department_permission_tenant_id", table_name="sys_department_permission")
    op.drop_table("sys_department_permission")
