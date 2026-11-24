"""多租户 RBAC 与店铺接入配置的 ORM 实体。"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class AuditFields:
    """后台配置实体共用审计字段与逻辑删除字段。"""

    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default=func.now(), onupdate=func.now())
    created_by: Mapped[int | None] = mapped_column(Integer, nullable=True)
    updated_by: Mapped[int | None] = mapped_column(Integer, nullable=True)
    deleted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")


class Org(AuditFields, Base):
    __tablename__ = "sys_org"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    org_code: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    org_name: Mapped[str] = mapped_column(String(128), nullable=False)
    domain: Mapped[str | None] = mapped_column(String(128), nullable=True)
    package_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    data_region: Mapped[str | None] = mapped_column(String(64), nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="ACTIVE")
    expire_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Department(AuditFields, Base):
    __tablename__ = "biz_department"
    __table_args__ = (UniqueConstraint("org_id", "dept_code", name="uq_department_org_code"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    org_id: Mapped[int] = mapped_column(ForeignKey("sys_org.id"), nullable=False, index=True)
    # 0 是总公司的根节点哨兵值；非 0 值由服务层校验为本租户的有效上级部门。
    parent_id: Mapped[int] = mapped_column(Integer, nullable=False, default=0, server_default="0")
    dept_name: Mapped[str] = mapped_column(String(128), nullable=False)
    dept_code: Mapped[str] = mapped_column(String(64), nullable=False)
    # 负责人身份关联：数据库层由 (org_id, manager_id) 复合外键保证同租户；
    # manager_name 是展示快照，实际以 manager_id 指向的有效用户为准。
    manager_id: Mapped[int | None] = mapped_column(Integer, ForeignKey("sys_user.id"), nullable=True, index=True)
    manager_name: Mapped[str | None] = mapped_column(String(64), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    email: Mapped[str | None] = mapped_column(String(128), nullable=True)
    sort: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="ENABLED")


class User(AuditFields, Base):
    __tablename__ = "sys_user"
    __table_args__ = (
        UniqueConstraint("org_id", "username", name="uq_user_org_username"),
        UniqueConstraint("org_id", "email", name="uq_user_org_email"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    org_id: Mapped[int] = mapped_column(ForeignKey("sys_org.id"), nullable=False, index=True)
    dept_id: Mapped[int | None] = mapped_column(ForeignKey("biz_department.id"), nullable=True, index=True)
    username: Mapped[str] = mapped_column(String(64), nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    real_name: Mapped[str] = mapped_column(String(64), nullable=False)
    email: Mapped[str | None] = mapped_column(String(128), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    data_scope: Mapped[str] = mapped_column(String(32), nullable=False, default="SELF")
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="ENABLED")
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)


class Role(AuditFields, Base):
    __tablename__ = "sys_role"
    __table_args__ = (UniqueConstraint("org_id", "role_code", name="uq_role_org_code"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    org_id: Mapped[int] = mapped_column(ForeignKey("sys_org.id"), nullable=False, index=True)
    role_name: Mapped[str] = mapped_column(String(64), nullable=False)
    role_code: Mapped[str] = mapped_column(String(64), nullable=False)
    description: Mapped[str | None] = mapped_column(String(512), nullable=True)
    data_scope: Mapped[str] = mapped_column(String(32), nullable=False, default="SELF")
    sort: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="ENABLED")


class Permission(AuditFields, Base):
    __tablename__ = "sys_permission"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    perm_name: Mapped[str] = mapped_column(String(128), nullable=False)
    perm_key: Mapped[str] = mapped_column(String(128), nullable=False, unique=True, index=True)
    description: Mapped[str | None] = mapped_column(String(512), nullable=True)
    module_name: Mapped[str] = mapped_column(String(64), nullable=False, default="未分类", server_default="未分类")
    perm_type: Mapped[str] = mapped_column(String(16), nullable=False, default="API")
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="ENABLED")


class UserRole(AuditFields, Base):
    __tablename__ = "sys_user_role"
    __table_args__ = (UniqueConstraint("user_id", "role_id", name="uq_user_role"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    org_id: Mapped[int] = mapped_column(ForeignKey("sys_org.id"), nullable=False, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("sys_user.id", ondelete="CASCADE"), nullable=False)
    role_id: Mapped[int] = mapped_column(ForeignKey("sys_role.id", ondelete="CASCADE"), nullable=False)


class RolePermission(AuditFields, Base):
    __tablename__ = "sys_role_permission"
    __table_args__ = (UniqueConstraint("role_id", "perm_id", name="uq_role_permission"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    role_id: Mapped[int] = mapped_column(ForeignKey("sys_role.id", ondelete="CASCADE"), nullable=False)
    perm_id: Mapped[int] = mapped_column(ForeignKey("sys_permission.id", ondelete="CASCADE"), nullable=False)


class DepartmentPermission(AuditFields, Base):
    """部门权限配置；不直接参与用户登录鉴权。"""

    __tablename__ = "sys_department_permission"
    __table_args__ = (
        UniqueConstraint("org_id", "dept_id", "perm_id", name="uq_department_permission"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    org_id: Mapped[int] = mapped_column(ForeignKey("sys_org.id"), nullable=False, index=True)
    dept_id: Mapped[int] = mapped_column(ForeignKey("biz_department.id", ondelete="CASCADE"), nullable=False)
    perm_id: Mapped[int] = mapped_column(ForeignKey("sys_permission.id", ondelete="CASCADE"), nullable=False)


class Shop(AuditFields, Base):
    __tablename__ = "biz_shop"
    __table_args__ = (UniqueConstraint("org_id", "shop_code", name="uq_shop_org_code"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    org_id: Mapped[int] = mapped_column(ForeignKey("sys_org.id"), nullable=False, index=True)
    dept_id: Mapped[int | None] = mapped_column(ForeignKey("biz_department.id"), nullable=True, index=True)
    shop_name: Mapped[str] = mapped_column(String(128), nullable=False)
    shop_code: Mapped[str] = mapped_column(String(64), nullable=False)
    platform: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="ENABLED")


class DepartmentShop(AuditFields, Base):
    """部门-店铺多对多关系：一个部门可管多店，一个店可被多个部门管理。"""

    __tablename__ = "biz_department_shop"
    __table_args__ = (UniqueConstraint("org_id", "dept_id", "shop_id", name="uq_dept_shop"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    org_id: Mapped[int] = mapped_column(ForeignKey("sys_org.id"), nullable=False, index=True)
    dept_id: Mapped[int] = mapped_column(ForeignKey("biz_department.id"), nullable=False, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("biz_shop.id"), nullable=False, index=True)


class UserShop(AuditFields, Base):
    __tablename__ = "sys_user_shop"
    __table_args__ = (UniqueConstraint("user_id", "shop_id", name="uq_user_shop"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    org_id: Mapped[int] = mapped_column(ForeignKey("sys_org.id"), nullable=False, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("sys_user.id", ondelete="CASCADE"), nullable=False)
    shop_id: Mapped[int] = mapped_column(ForeignKey("biz_shop.id", ondelete="CASCADE"), nullable=False)


class PlatformConfig(AuditFields, Base):
    __tablename__ = "biz_platform_config"
    __table_args__ = (UniqueConstraint("org_id", "shop_id", name="uq_platform_config_shop"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    org_id: Mapped[int] = mapped_column(ForeignKey("sys_org.id"), nullable=False, index=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("biz_shop.id", ondelete="CASCADE"), nullable=False)
    platform: Mapped[str] = mapped_column(String(32), nullable=False)
    api_key_secret: Mapped[str | None] = mapped_column(Text, nullable=True)
    api_secret_secret: Mapped[str | None] = mapped_column(Text, nullable=True)
    access_token_secret: Mapped[str | None] = mapped_column(Text, nullable=True)
    api_base_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    callback_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="ENABLED")
