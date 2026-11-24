"""建立多租户 RBAC、店铺授权和平台连接配置表。

Revision ID: 0002_rbac_multitenancy
Revises: 0001_initial
Create Date: 2026-11-23
"""

from alembic import op
import sqlalchemy as sa


revision = "0002_rbac_multitenancy"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def _audit_columns() -> list[sa.Column]:
    return [
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("created_by", sa.Integer(), nullable=True),
        sa.Column("updated_by", sa.Integer(), nullable=True),
        sa.Column("deleted", sa.Boolean(), nullable=False, server_default=sa.false()),
    ]


def upgrade() -> None:
    op.create_table(
        "sys_tenant",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("tenant_code", sa.String(64), nullable=False),
        sa.Column("tenant_name", sa.String(128), nullable=False),
        sa.Column("domain", sa.String(128)), sa.Column("package_code", sa.String(64)),
        sa.Column("data_region", sa.String(64)), sa.Column("status", sa.String(16), nullable=False, server_default="ACTIVE"),
        sa.Column("expire_at", sa.DateTime()), *_audit_columns(),
        sa.UniqueConstraint("tenant_code", name="uq_sys_tenant_code"),
    )
    op.create_table(
        "biz_department",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("tenant_id", sa.Integer(), sa.ForeignKey("sys_tenant.id"), nullable=False),
        sa.Column("parent_id", sa.Integer(), sa.ForeignKey("biz_department.id")),
        sa.Column("dept_name", sa.String(128), nullable=False), sa.Column("dept_code", sa.String(64), nullable=False),
        sa.Column("manager_name", sa.String(64)), sa.Column("phone", sa.String(32)), sa.Column("email", sa.String(128)),
        sa.Column("sort", sa.Integer(), nullable=False, server_default="0"), sa.Column("status", sa.String(16), nullable=False, server_default="ENABLED"),
        *_audit_columns(), sa.UniqueConstraint("tenant_id", "dept_code", name="uq_department_tenant_code"),
    )
    op.create_table(
        "sys_user",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("tenant_id", sa.Integer(), sa.ForeignKey("sys_tenant.id"), nullable=False),
        sa.Column("dept_id", sa.Integer(), sa.ForeignKey("biz_department.id")),
        sa.Column("username", sa.String(64), nullable=False), sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("real_name", sa.String(64), nullable=False), sa.Column("email", sa.String(128)), sa.Column("phone", sa.String(32)),
        sa.Column("data_scope", sa.String(32), nullable=False, server_default="SELF"),
        sa.Column("status", sa.String(16), nullable=False, server_default="ENABLED"), sa.Column("last_login_at", sa.DateTime()),
        *_audit_columns(), sa.UniqueConstraint("tenant_id", "username", name="uq_user_tenant_username"),
        sa.UniqueConstraint("tenant_id", "email", name="uq_user_tenant_email"),
    )
    op.create_table(
        "sys_role",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("tenant_id", sa.Integer(), sa.ForeignKey("sys_tenant.id"), nullable=False),
        sa.Column("role_name", sa.String(64), nullable=False), sa.Column("role_code", sa.String(64), nullable=False),
        sa.Column("description", sa.String(512)), sa.Column("data_scope", sa.String(32), nullable=False, server_default="SELF"),
        sa.Column("sort", sa.Integer(), nullable=False, server_default="0"), sa.Column("status", sa.String(16), nullable=False, server_default="ENABLED"),
        *_audit_columns(), sa.UniqueConstraint("tenant_id", "role_code", name="uq_role_tenant_code"),
    )
    op.create_table(
        "sys_permission",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("parent_id", sa.Integer(), sa.ForeignKey("sys_permission.id")),
        sa.Column("perm_name", sa.String(128), nullable=False), sa.Column("perm_key", sa.String(128), nullable=False),
        sa.Column("perm_type", sa.String(16), nullable=False, server_default="API"), sa.Column("status", sa.String(16), nullable=False, server_default="ENABLED"),
        *_audit_columns(), sa.UniqueConstraint("perm_key", name="uq_sys_permission_key"),
    )
    op.create_table(
        "sys_user_role",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("tenant_id", sa.Integer(), sa.ForeignKey("sys_tenant.id"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("sys_user.id", ondelete="CASCADE"), nullable=False),
        sa.Column("role_id", sa.Integer(), sa.ForeignKey("sys_role.id", ondelete="CASCADE"), nullable=False),
        *_audit_columns(), sa.UniqueConstraint("user_id", "role_id", name="uq_user_role"),
    )
    op.create_table(
        "sys_role_permission",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("role_id", sa.Integer(), sa.ForeignKey("sys_role.id", ondelete="CASCADE"), nullable=False),
        sa.Column("perm_id", sa.Integer(), sa.ForeignKey("sys_permission.id", ondelete="CASCADE"), nullable=False),
        *_audit_columns(), sa.UniqueConstraint("role_id", "perm_id", name="uq_role_permission"),
    )
    op.create_table(
        "biz_shop",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("tenant_id", sa.Integer(), sa.ForeignKey("sys_tenant.id"), nullable=False),
        sa.Column("dept_id", sa.Integer(), sa.ForeignKey("biz_department.id")),
        sa.Column("shop_name", sa.String(128), nullable=False), sa.Column("shop_code", sa.String(64), nullable=False),
        sa.Column("platform", sa.String(32), nullable=False), sa.Column("status", sa.String(16), nullable=False, server_default="ENABLED"),
        *_audit_columns(), sa.UniqueConstraint("tenant_id", "shop_code", name="uq_shop_tenant_code"),
    )
    op.create_table(
        "sys_user_shop",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("tenant_id", sa.Integer(), sa.ForeignKey("sys_tenant.id"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("sys_user.id", ondelete="CASCADE"), nullable=False),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("biz_shop.id", ondelete="CASCADE"), nullable=False),
        *_audit_columns(), sa.UniqueConstraint("user_id", "shop_id", name="uq_user_shop"),
    )
    op.create_table(
        "biz_platform_config",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("tenant_id", sa.Integer(), sa.ForeignKey("sys_tenant.id"), nullable=False),
        sa.Column("shop_id", sa.Integer(), sa.ForeignKey("biz_shop.id", ondelete="CASCADE"), nullable=False),
        sa.Column("platform", sa.String(32), nullable=False), sa.Column("api_key_secret", sa.Text()),
        sa.Column("api_secret_secret", sa.Text()), sa.Column("access_token_secret", sa.Text()),
        sa.Column("api_base_url", sa.String(512)), sa.Column("callback_url", sa.String(512)),
        sa.Column("status", sa.String(16), nullable=False, server_default="ENABLED"), *_audit_columns(),
        sa.UniqueConstraint("tenant_id", "shop_id", name="uq_platform_config_shop"),
    )
    for table in ("biz_department", "sys_user", "sys_role", "sys_user_role", "biz_shop", "sys_user_shop", "biz_platform_config"):
        op.create_index(f"ix_{table}_tenant_id", table, ["tenant_id"])
    op.bulk_insert(sa.table("sys_permission", sa.column("perm_key", sa.String()), sa.column("perm_name", sa.String()), sa.column("perm_type", sa.String()), sa.column("status", sa.String())), [
        {"perm_key": key, "perm_name": name, "perm_type": "API", "status": "ENABLED"}
        for key, name in [
            ("cs:goods:import", "下载导入推荐商品"), ("cs:goods:rebuildIndex", "重建向量商品索引"), ("cs:mock:sendMsg", "模拟买家发送消息"),
            ("cs:session:view", "查看会话与意图"), ("cs:session:takeover", "人工接管会话"), ("cs:session:translateReview", "翻译复核回复"),
            ("cs:ticket:create", "创建售后工单"), ("cs:ticket:view", "查看售后工单"), ("cs:ticket:audit", "售后工单审批"),
            ("bi:dashboard:design", "编排 BI 驾驶舱"), ("bi:dashboard:saveDraft", "保存驾驶舱草稿"), ("bi:dashboard:publish", "发布驾驶舱"),
            ("bi:dashboard:view", "查看已发布驾驶舱"), ("bi:query:ask", "自然语言问数查询"), ("bi:metric:edit", "维护指标口径与知识库"),
            ("forecast:sales:run", "执行 SKU 销量预测"), ("forecast:sales:editActual", "采集 & 人工修正实际销量"), ("forecast:model:manage", "模型注册启停管理"),
            ("product:source:upload", "登记 & 导入选品数据源"), ("product:research:view", "查看选品研究档案"), ("product:research:audit", "选品测款人工决策"),
            ("replenish:plan:submit", "补货方案测算 & 提交计划"), ("replenish:cost:edit", "维护成本卡凭证"), ("replenish:plan:audit", "补货计划审批"),
            ("replenish:purchase:create", "创建内部采购任务"), ("replenish:receive:save", "登记收货质检凭证"), ("replenish:deliver:save", "登记发货运单"),
            ("replenish:audit:view", "复盘审计查看"), ("system:tenant:roleManage", "角色租户管理"),
        ]
    ])


def downgrade() -> None:
    for table in ("biz_platform_config", "sys_user_shop", "biz_shop", "sys_role_permission", "sys_user_role", "sys_permission", "sys_role", "sys_user", "biz_department", "sys_tenant"):
        op.drop_table(table)
