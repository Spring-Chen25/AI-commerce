"""RBAC 鉴权、租户上下文与数据权限依赖。"""

from dataclasses import dataclass
from typing import Callable

from fastapi import Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.exceptions import ForbiddenException, UnauthorizedException
from app.models.rbac import Permission, Role, RolePermission, Org, User, UserRole
from app.utils.dependencies import get_current_user


@dataclass(frozen=True)
class Principal:
    user_id: int
    org_id: int
    username: str
    role_codes: frozenset[str]
    permission_keys: frozenset[str]
    data_scope: str

    @property
    def is_super_admin(self) -> bool:
        return "SUPER_ADMIN" in self.role_codes


def resolve_principal(payload: dict, db: Session) -> Principal:
    """从已签名令牌重新读取有效用户和角色，避免权限变更后旧令牌越权。"""
    try:
        user_id = int(payload["user_id"])
    except (KeyError, TypeError, ValueError) as exc:
        raise UnauthorizedException("令牌用户标识无效") from exc

    user = db.scalar(
        select(User).where(User.id == user_id, User.deleted.is_(False), User.status == "ENABLED")
    )
    if user is None:
        raise UnauthorizedException("用户不存在或已停用")
    org = db.scalar(
        select(Org).where(Org.id == user.org_id, Org.deleted.is_(False), Org.status == "ACTIVE")
    )
    if org is None:
        raise UnauthorizedException("租户不存在或不可用")

    roles = db.scalars(
        select(Role).join(UserRole, UserRole.role_id == Role.id).where(
            UserRole.user_id == user.id,
            UserRole.org_id == user.org_id,
            UserRole.deleted.is_(False),
            Role.org_id == user.org_id,
            Role.deleted.is_(False),
            Role.status == "ENABLED",
        )
    ).all()
    role_codes = frozenset(role.role_code for role in roles)
    if "SUPER_ADMIN" in role_codes:
        permission_keys = frozenset(db.scalars(select(Permission.perm_key).where(
            Permission.status == "ENABLED", Permission.deleted.is_(False)
        )).all())
    else:
        permission_keys = frozenset(
            db.scalars(
                select(Permission.perm_key)
                .join(RolePermission, RolePermission.perm_id == Permission.id)
                .join(Role, Role.id == RolePermission.role_id)
                .join(UserRole, UserRole.role_id == Role.id)
                .where(
                    UserRole.user_id == user.id,
                    UserRole.org_id == user.org_id,
                    UserRole.deleted.is_(False),
                    Role.org_id == user.org_id,
                    Role.deleted.is_(False),
                    Role.status == "ENABLED",
                    RolePermission.deleted.is_(False),
                    Permission.status == "ENABLED",
                    Permission.deleted.is_(False),
                )
            ).all()
        )
    return Principal(
        user_id=user.id,
        org_id=user.org_id,
        username=user.username,
        role_codes=role_codes,
        permission_keys=permission_keys,
        data_scope=user.data_scope,
    )


def get_principal(
    payload: dict = Depends(get_current_user), db: Session = Depends(get_db)
) -> Principal:
    return resolve_principal(payload, db)


def require_permission(permission_key: str) -> Callable:
    """返回声明式接口权限依赖；超级管理员由角色直接放行。"""

    def dependency(principal: Principal = Depends(get_principal)) -> Principal:
        if not principal.is_super_admin and permission_key not in principal.permission_keys:
            raise ForbiddenException(f"缺少权限: {permission_key}")
        return principal

    return dependency
