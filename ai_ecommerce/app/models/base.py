"""多数据库模型基类预留。

约定：
- 模型按数据库物理分目录：mysql/ 子包放 MySQL 模型，pgsql/ 子包放 PostgreSQL 模型。
- 每个模型继承 database.Base，并声明 __bind_key__（可继承 BindKeyMixin 获得该标记）。
- 实际分库路由由 DAO 层依据 model.__bind_key__ 选择对应 session，目录本身不自动分库。
"""

from app.database import Base  # noqa: F401  统一从此处导入，便于将来切换基类


class BindKeyMixin:
    """分库标记 mixin：子类声明 __bind_key__ = "pgsql" / "mysql" 等。

    仅为约定载体，不含 ORM 行为；DAO 依据 __bind_key__ 选择会话工厂。
    """

    __bind_key__: str = "default"
