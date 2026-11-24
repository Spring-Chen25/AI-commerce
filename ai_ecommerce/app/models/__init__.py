"""SQLAlchemy ORM 模型集合。

按数据库物理分子包：
- base.py   公共基类导出 + BindKeyMixin（逻辑分库标记，__bind_key__）
- audit.py  审计表（绑默认库）
- mysql/    MySQL 业务模型子包（预留空包）
- pgsql/    PostgreSQL 业务模型子包（预留空包）

新增业务模型时：放入对应子包 → 在子包 __init__.py 导入 → 在此汇总导入，
便于 Alembic autogenerate 发现全部表。
"""

from app.models import base  # noqa: F401
from app.models import audit  # noqa: F401  审计表，autogenerate 需发现
from app.models import mysql  # noqa: F401  MySQL 模型子包
from app.models import pgsql  # noqa: F401  PostgreSQL 模型子包
from app.models import rbac  # noqa: F401  租户、RBAC 与店铺接入配置

__all__ = ["base", "audit", "mysql", "pgsql", "rbac"]
