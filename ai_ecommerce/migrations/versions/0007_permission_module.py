"""保存《项目权限表》的所属 Agent 模块。

Revision ID: 0007_permission_module
Revises: 0006_tenant_relation_integrity
"""

from alembic import op
import sqlalchemy as sa


revision = "0007_permission_module"
down_revision = "0006_tenant_relation_integrity"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("sys_permission", sa.Column(
        "module_name", sa.String(64), nullable=False, server_default="未分类",
    ))
    op.execute("""UPDATE sys_permission SET module_name = CASE
        WHEN perm_key LIKE 'cs:%' THEN '智能客服 Agent'
        WHEN perm_key LIKE 'bi:dashboard:%' THEN '驾驶舱设计 Agent'
        WHEN perm_key LIKE 'bi:%' THEN '智能问数 Agent'
        WHEN perm_key LIKE 'forecast:%' THEN '销量预测 Agent'
        WHEN perm_key LIKE 'product:%' THEN '选品分析 Agent'
        WHEN perm_key LIKE 'replenish:%' THEN '补货预测 Agent'
        WHEN perm_key LIKE 'system:%' THEN '系统管理'
        ELSE '未分类' END""")


def downgrade() -> None:
    op.drop_column("sys_permission", "module_name")
