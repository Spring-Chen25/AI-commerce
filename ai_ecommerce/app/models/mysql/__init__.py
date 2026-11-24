"""MySQL 业务模型子包。

约定：
- 本包内只放绑定 MySQL 库的 ORM 模型（物理分目录）。
- 每个模型继承 app.database.Base，并声明 __bind_key__ = "mysql"
  （可继承 app.models.base.BindKeyMixin 快速获得该标记）。
- 分库路由由 DAO 层依据 __bind_key__ 选择对应 session，目录本身不自动分库。
- 新增模型后在此导入，便于上层汇总导出与 Alembic autogenerate 发现。

当前为预留空包，待 MySQL 业务模型落地后填充。
"""

# from .xxx import Xxx  # noqa: F401  新增模型在此导入
