"""RBAC 业务服务：执行租户归属校验、授权变更与敏感字段脱敏。"""

from datetime import datetime, timezone

from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session

from app.dao.rbac import OrgRepository
from app.exceptions import ConflictException, NotFoundException, ValidationException
from app.models.rbac import (
    Department, DepartmentPermission, DepartmentShop, Permission, PlatformConfig, Role, RolePermission,
    Shop, Org, User, UserRole, UserShop,
)
from app.services.rbac_seed import seed_org_roles
from app.utils.credentials import encrypt_secret
from app.utils.security import hash_password


def _active(model, record_id: int, org_id: int, db: Session):
    record = db.scalar(select(model).where(model.id == record_id, model.org_id == org_id, model.deleted.is_(False)))
    if record is None:
        raise NotFoundException("资源不存在或不属于当前租户")
    return record


def _ensure_department(dept_id: int | None, org_id: int, db: Session) -> None:
    if dept_id is not None:
        _active(Department, dept_id, org_id, db)


def _resolve_manager(values: dict, org_id: int, db: Session) -> None:
    """规范部门负责人：校验同租户有效用户，并让展示名与用户表保持一致。"""
    if "manager_id" not in values:
        return
    manager_id = values["manager_id"]
    if manager_id is None:
        values["manager_name"] = None
        values["manager_id"] = None
        return
    manager = db.scalar(select(User).where(
        User.id == manager_id, User.org_id == org_id,
        User.deleted.is_(False), User.status == "ENABLED",
    ))
    if manager is None:
        raise ValidationException("负责人必须属于当前租户且为启用状态的用户")
    values["manager_id"] = manager.id
    # manager_name 只作为展示快照，始终以用户表实时姓名为准，避免改名不同步。
    values["manager_name"] = manager.real_name


def _mask(value: str | None) -> str | None:
    if not value:
        return None
    return "*" * max(4, min(len(value), 12))


class RbacService:
    def __init__(self, db: Session, org_id: int, actor_id: int):
        self.db, self.org_id, self.actor_id = db, org_id, actor_id

    def _repo(self, model):
        return OrgRepository(self.db, model, self.org_id)

    def create_department(self, values: dict) -> Department:
        parent_id = values.get("parent_id", 0)
        if parent_id != 0:
            if parent_id == values.get("id"):
                raise ValidationException("部门不能指定自己为上级")
            _active(Department, parent_id, self.org_id, self.db)
        _resolve_manager(values, self.org_id, self.db)
        return self._repo(Department).create(values, self.actor_id)

    def update_department(self, record_id: int, values: dict) -> Department:
        record = _active(Department, record_id, self.org_id, self.db)
        parent_id = values.get("parent_id", record.parent_id)
        if parent_id == record_id:
            raise ValidationException("部门不能指定自己为上级")
        if parent_id != 0:
            _active(Department, parent_id, self.org_id, self.db)
            ancestor_id = parent_id
            while ancestor_id != 0:
                if ancestor_id == record_id:
                    raise ValidationException("部门层级不能形成循环")
                ancestor = _active(Department, ancestor_id, self.org_id, self.db)
                ancestor_id = ancestor.parent_id
        _resolve_manager(values, self.org_id, self.db)
        return self._repo(Department).update(record, values, self.actor_id)

    def assign_department_permissions(self, dept_id: int, permission_ids: list[int]) -> None:
        """设置部门权限配置，不改变成员的有效角色权限。"""
        _active(Department, dept_id, self.org_id, self.db)
        for perm_id in set(permission_ids):
            permission = self.db.scalar(select(Permission).where(
                Permission.id == perm_id, Permission.deleted.is_(False), Permission.status == "ENABLED"
            ))
            if permission is None:
                raise NotFoundException("权限不存在或已停用")
        self.db.execute(delete(DepartmentPermission).where(
            DepartmentPermission.org_id == self.org_id,
            DepartmentPermission.dept_id == dept_id,
        ))
        self.db.add_all([
            DepartmentPermission(org_id=self.org_id, dept_id=dept_id, perm_id=perm_id,
                                 created_by=self.actor_id)
            for perm_id in set(permission_ids)
        ])

    def delete_department(self, dept_id: int) -> None:
        """有下级部门、用户或店铺时禁止删除，维护组织关联完整性。"""
        record = _active(Department, dept_id, self.org_id, self.db)
        if self.db.scalar(select(Department.id).where(
            Department.parent_id == dept_id, Department.org_id == self.org_id,
            Department.deleted.is_(False), Department.id != dept_id
        ).limit(1)) is not None:
            raise ConflictException("请先迁移下级部门")
        if self.db.scalar(select(User.id).where(
            User.dept_id == dept_id, User.org_id == self.org_id, User.deleted.is_(False)
        ).limit(1)) is not None:
            raise ConflictException("请先迁移部门用户")
        if self.db.scalar(select(DepartmentShop.id).where(
            DepartmentShop.dept_id == dept_id, DepartmentShop.org_id == self.org_id,
            DepartmentShop.deleted.is_(False)
        ).limit(1)) is not None:
            raise ConflictException("请先迁移部门店铺")
        self._repo(Department).delete(record, self.actor_id)

    def assign_department_shops(self, dept_id: int, shop_ids: list[int]) -> None:
        """以完整店铺列表替换【本部门】的店铺关系，不影响其他部门已分配的店铺。

        一个部门可管多店、一个店可被多个部门管；biz_shop.dept_id 仅作主归属展示，不再抢占改写。
        """
        _active(Department, dept_id, self.org_id, self.db)
        selected = set(shop_ids)
        known = set(self.db.scalars(select(Shop.id).where(
            Shop.org_id == self.org_id, Shop.deleted.is_(False)
        )).all())
        if not selected.issubset(known):
            raise NotFoundException("包含不存在或不属于当前租户的店铺")

        # 仅移除本部门不再勾选的关联，其他部门的关联保持不动
        existing = self.db.scalars(select(DepartmentShop).where(
            DepartmentShop.org_id == self.org_id,
            DepartmentShop.dept_id == dept_id,
            DepartmentShop.deleted.is_(False),
        )).all()
        for rel in existing:
            if rel.shop_id not in selected:
                self.db.delete(rel)
        current = {rel.shop_id for rel in existing}
        for shop_id in selected - current:
            self.db.add(DepartmentShop(
                org_id=self.org_id, dept_id=dept_id, shop_id=shop_id,
                created_by=self.actor_id, updated_by=self.actor_id,
            ))
        self.db.flush()

    def create_user(self, values: dict) -> User:
        _ensure_department(values.get("dept_id"), self.org_id, self.db)
        for key in ("email", "phone"):
            if key in values:
                values[key] = (values[key] or "").strip() or None
        values["password_hash"] = hash_password(values.pop("password"))
        return self._repo(User).create(values, self.actor_id)

    def update_user(self, record_id: int, values: dict) -> User:
        _ensure_department(values.get("dept_id"), self.org_id, self.db)
        for key in ("email", "phone"):
            if key in values:
                values[key] = (values[key] or "").strip() or None
        record = _active(User, record_id, self.org_id, self.db)
        return self._repo(User).update(record, values, self.actor_id)

    def reset_password(self, record_id: int, password: str) -> None:
        record = _active(User, record_id, self.org_id, self.db)
        record.password_hash = hash_password(password)
        record.updated_by = self.actor_id
        self.db.flush()

    def delete_user(self, record_id: int) -> None:
        """逻辑删除当前租户用户，同时撤销角色和店铺关联。"""
        record = _active(User, record_id, self.org_id, self.db)
        if record.id == self.actor_id:
            raise ValidationException("不能删除当前登录用户")
        is_admin = self.db.scalar(select(UserRole.id).join(Role, Role.id == UserRole.role_id).where(
            UserRole.org_id == self.org_id, UserRole.user_id == record_id,
            UserRole.deleted.is_(False), Role.role_code == "SUPER_ADMIN",
            Role.deleted.is_(False), Role.status == "ENABLED",
        ).limit(1)) is not None
        if is_admin:
            other_admin = self.db.scalar(select(User.id).join(UserRole, UserRole.user_id == User.id)
                .join(Role, Role.id == UserRole.role_id).where(
                    User.org_id == self.org_id, User.id != record_id,
                    User.deleted.is_(False), User.status == "ENABLED",
                    UserRole.deleted.is_(False), Role.role_code == "SUPER_ADMIN",
                    Role.deleted.is_(False), Role.status == "ENABLED",
                ).limit(1))
            if other_admin is None:
                raise ValidationException("不能删除租户最后一名超级管理员")
        self.db.execute(update(UserRole).where(
            UserRole.org_id == self.org_id, UserRole.user_id == record_id,
            UserRole.deleted.is_(False),
        ).values(deleted=True, updated_by=self.actor_id))
        self.db.execute(update(UserShop).where(
            UserShop.org_id == self.org_id, UserShop.user_id == record_id,
            UserShop.deleted.is_(False),
        ).values(deleted=True, updated_by=self.actor_id))
        self._repo(User).delete(record, self.actor_id)


    def assign_user_roles(self, user_id: int, role_ids: list[int]) -> None:
        _active(User, user_id, self.org_id, self.db)
        for role_id in set(role_ids):
            _active(Role, role_id, self.org_id, self.db)
        self.db.execute(delete(UserRole).where(UserRole.user_id == user_id))
        self.db.add_all([UserRole(org_id=self.org_id, user_id=user_id, role_id=role_id, created_by=self.actor_id) for role_id in set(role_ids)])

    def assign_user_shops(self, user_id: int, shop_ids: list[int]) -> None:
        _active(User, user_id, self.org_id, self.db)
        for shop_id in set(shop_ids):
            _active(Shop, shop_id, self.org_id, self.db)
        self.db.execute(delete(UserShop).where(UserShop.user_id == user_id))
        self.db.add_all([UserShop(org_id=self.org_id, user_id=user_id, shop_id=shop_id, created_by=self.actor_id) for shop_id in set(shop_ids)])

    def create_role(self, values: dict) -> Role:
        return self._repo(Role).create(values, self.actor_id)

    def update_role(self, record_id: int, values: dict) -> Role:
        return self._repo(Role).update(_active(Role, record_id, self.org_id, self.db), values, self.actor_id)

    def delete_role(self, record_id: int) -> None:
        """仅允许删除未分配给有效用户的普通角色。"""
        role = _active(Role, record_id, self.org_id, self.db)
        if role.role_code == "SUPER_ADMIN":
            raise ValidationException("超级管理员角色不能删除")
        assigned_user = self.db.scalar(select(User.id).join(UserRole, UserRole.user_id == User.id).where(
            UserRole.org_id == self.org_id, UserRole.role_id == record_id,
            UserRole.deleted.is_(False), User.org_id == self.org_id,
            User.deleted.is_(False),
        ).limit(1))
        if assigned_user is not None:
            raise ConflictException("该角色已分配给用户，请先调整用户角色")
        self.db.execute(update(RolePermission).where(
            RolePermission.role_id == record_id, RolePermission.deleted.is_(False),
        ).values(deleted=True, updated_by=self.actor_id))
        self._repo(Role).delete(role, self.actor_id)


    def assign_role_permissions(self, role_id: int, permission_ids: list[int]) -> None:
        _active(Role, role_id, self.org_id, self.db)
        existing = set(self.db.scalars(select(Permission.id).where(Permission.id.in_(set(permission_ids)), Permission.deleted.is_(False))).all()) if permission_ids else set()
        if existing != set(permission_ids):
            raise ValidationException("包含不存在或已删除的权限")
        self.db.execute(delete(RolePermission).where(RolePermission.role_id == role_id))
        self.db.add_all([RolePermission(role_id=role_id, perm_id=perm_id, created_by=self.actor_id) for perm_id in existing])

    def create_shop(self, values: dict) -> Shop:
        _ensure_department(values.get("dept_id"), self.org_id, self.db)
        return self._repo(Shop).create(values, self.actor_id)

    def update_shop(self, record_id: int, values: dict) -> Shop:
        _ensure_department(values.get("dept_id"), self.org_id, self.db)
        return self._repo(Shop).update(_active(Shop, record_id, self.org_id, self.db), values, self.actor_id)

    def save_platform_config(self, record_id: int | None, values: dict) -> PlatformConfig:
        _active(Shop, values["shop_id"], self.org_id, self.db)
        secret_values = {
            "api_key": "api_key_secret", "api_secret": "api_secret_secret", "access_token": "access_token_secret",
        }
        normalized = {key: value for key, value in values.items() if key not in secret_values}
        for input_key, target_key in secret_values.items():
            if values.get(input_key) is not None:
                normalized[target_key] = encrypt_secret(values[input_key])
        if record_id is None:
            return self._repo(PlatformConfig).create(normalized, self.actor_id)
        return self._repo(PlatformConfig).update(_active(PlatformConfig, record_id, self.org_id, self.db), normalized, self.actor_id)

    @staticmethod
    def config_out(item: PlatformConfig) -> dict:
        return {
            "id": item.id, "org_id": item.org_id, "shop_id": item.shop_id, "platform": item.platform,
            "api_key_masked": _mask(item.api_key_secret), "api_secret_masked": _mask(item.api_secret_secret),
            "access_token_masked": _mask(item.access_token_secret), "api_base_url": item.api_base_url,
            "callback_url": item.callback_url, "status": item.status,
        }


def bootstrap(db: Session, org_code: str, org_name: str, username: str, password: str, real_name: str) -> User:
    """仅允许首个用户初始化系统，避免公开注册成为越权入口。"""
    if db.scalar(select(User.id).limit(1)) is not None:
        raise ConflictException("系统已初始化，不能重复创建首个管理员")
    org = db.scalar(select(Org).where(Org.org_code == org_code, Org.deleted.is_(False)))
    if org is None:
        org = Org(org_code=org_code, org_name=org_name, status="ACTIVE")
        db.add(org)
        db.flush()
    seed_org_roles(db, org.id)
    super_role = db.scalar(select(Role).where(Role.org_id == org.id, Role.role_code == "SUPER_ADMIN"))
    user = User(
        org_id=org.id, username=username, password_hash=hash_password(password), real_name=real_name,
        data_scope="ALL", status="ENABLED",
    )
    db.add(user)
    db.flush()
    db.add(UserRole(org_id=org.id, user_id=user.id, role_id=super_role.id, created_by=user.id))
    return user


def register_user(db: Session, org_code: str, values: dict) -> User:
    """在已有租户中自助注册；待管理员启用并分配角色后才能登录。"""
    org = db.scalar(select(Org).where(
        Org.org_code == org_code.strip(), Org.deleted.is_(False), Org.status == "ACTIVE",
    ))
    if org is None:
        raise NotFoundException("租户不存在或不可用")
    username = values["username"].strip()
    real_name = values["real_name"].strip()
    if not username or not real_name:
        raise ValidationException("用户名和姓名不能为空")
    email = (values.get("email") or "").strip() or None
    phone = (values.get("phone") or "").strip() or None
    if db.scalar(select(User.id).where(User.org_id == org.id, User.username == username)) is not None:
        raise ConflictException("用户名已存在")
    if email and db.scalar(select(User.id).where(User.org_id == org.id, User.email == email)) is not None:
        raise ConflictException("邮箱已存在")
    user = User(
        org_id=org.id, username=username, real_name=real_name,
        password_hash=hash_password(values["password"]), email=email, phone=phone,
        data_scope="SELF", status="DISABLED",
    )
    db.add(user)
    db.flush()
    user.created_by = user.id
    user.updated_by = user.id
    return user


def create_org(db: Session, values: dict, actor_id: int) -> Org:
    org = Org(**values, created_by=actor_id, updated_by=actor_id)
    db.add(org)
    db.flush()
    seed_org_roles(db, org.id, actor_id)
    return org


def touch_login(user: User) -> None:
    user.last_login_at = datetime.now(timezone.utc).replace(tzinfo=None)
