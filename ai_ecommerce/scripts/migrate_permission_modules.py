"""仅依据项目权限表补齐 sys_permission 所属模块，不重置种子账号或授权。"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg

from init_rbac_postgres import read_csv
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.config import settings


def main() -> None:
    dsn = os.environ.get("RBAC_DATABASE_URL") or settings.DATABASE_URL.replace("postgresql+psycopg://", "postgresql://", 1)
    if not dsn.startswith("postgresql://"):
        raise SystemExit("本迁移仅支持 PostgreSQL；请在 .env 中配置 DATABASE_URL 或设置 RBAC_DATABASE_URL")
    rows = [row for row in read_csv("项目权限表.csv") if row.get("perm_key")]
    with psycopg.connect(dsn) as conn:
        with conn.cursor() as cur:
            cur.execute("ALTER TABLE sys_permission ADD COLUMN IF NOT EXISTS module_name VARCHAR(64) NOT NULL DEFAULT '未分类'")
            cur.execute("COMMENT ON COLUMN sys_permission.module_name IS '项目权限表所属 Agent 模块或系统管理分类'")
            matched = 0
            for row in rows:
                cur.execute(
                    "UPDATE sys_permission SET module_name = %s WHERE perm_key = %s",
                    (row["所属模块"], row["perm_key"]),
                )
                matched += cur.rowcount
            if matched != len(rows):
                raise RuntimeError(f"权限目录与项目权限表不一致：匹配 {matched}/{len(rows)} 项，事务已回滚")
            cur.execute("SELECT module_name, COUNT(*) FROM sys_permission WHERE deleted = FALSE GROUP BY module_name ORDER BY module_name")
            counts = cur.fetchall()
        conn.commit()
    print(f"已更新 {matched} 项权限的所属模块：{counts}")


if __name__ == "__main__":
    main()
