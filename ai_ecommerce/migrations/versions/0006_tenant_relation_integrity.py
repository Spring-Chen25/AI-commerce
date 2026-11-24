"""Enforce same-tenant relationships for RBAC and shop references.

Revision ID: 0006_tenant_relation_integrity
Revises: 0005_department_permission
"""

from alembic import op


revision = "0006_tenant_relation_integrity"
down_revision = "0005_department_permission"
branch_labels = None
depends_on = None

TENANT_KEY_TABLES = ("biz_department", "sys_user", "sys_role", "biz_shop")
TENANT_FOREIGN_KEYS = (
    ("sys_user", "dept_id", "biz_department", False),
    ("biz_shop", "dept_id", "biz_department", False),
    ("sys_user_role", "user_id", "sys_user", True),
    ("sys_user_role", "role_id", "sys_role", True),
    ("sys_user_shop", "user_id", "sys_user", True),
    ("sys_user_shop", "shop_id", "biz_shop", True),
    ("sys_department_permission", "dept_id", "biz_department", True),
    ("biz_platform_config", "shop_id", "biz_shop", True),
)


def upgrade() -> None:
    for table in TENANT_KEY_TABLES:
        op.execute(f"CREATE UNIQUE INDEX IF NOT EXISTS ux_{table}_tenant_id_id ON {table}(tenant_id, id)")
    for table, column, target, cascade in TENANT_FOREIGN_KEYS:
        constraint = f"fk_{table}_{column}_tenant"
        action = " ON DELETE CASCADE" if cascade else ""
        op.execute(f"""DO $$ BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = '{constraint}'
                           AND conrelid = '{table}'::regclass) THEN
                ALTER TABLE {table} ADD CONSTRAINT {constraint}
                FOREIGN KEY (tenant_id, {column}) REFERENCES {target}(tenant_id, id){action};
            END IF;
        END $$""")
    op.execute("""CREATE OR REPLACE FUNCTION check_department_parent_tenant() RETURNS trigger AS $$
        BEGIN
            IF NEW.parent_id <> 0 THEN
                IF NEW.parent_id = NEW.id OR NOT EXISTS (
                    SELECT 1 FROM biz_department p WHERE p.id = NEW.parent_id
                      AND p.tenant_id = NEW.tenant_id AND p.deleted = FALSE
                ) THEN
                    RAISE EXCEPTION 'parent department must be active and in the same tenant';
                END IF;
            END IF;
            RETURN NEW;
        END; $$ LANGUAGE plpgsql""")
    op.execute("DROP TRIGGER IF EXISTS trg_department_parent_tenant ON biz_department")
    op.execute("""CREATE TRIGGER trg_department_parent_tenant BEFORE INSERT OR UPDATE OF parent_id, tenant_id
        ON biz_department FOR EACH ROW EXECUTE FUNCTION check_department_parent_tenant()""")


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS trg_department_parent_tenant ON biz_department")
    op.execute("DROP FUNCTION IF EXISTS check_department_parent_tenant()")
    for table, column, _, _ in reversed(TENANT_FOREIGN_KEYS):
        op.execute(f"ALTER TABLE {table} DROP CONSTRAINT IF EXISTS fk_{table}_{column}_tenant")
    for table in reversed(TENANT_KEY_TABLES):
        op.execute(f"DROP INDEX IF EXISTS ux_{table}_tenant_id_id")
