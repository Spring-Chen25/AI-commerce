"""RBAC 类式路由：认证、租户、部门、角色、用户、店铺与平台配置。"""

from fastapi import Depends, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.exceptions import ConflictException, NotFoundException, UnauthorizedException, ValidationException
from app.models.rbac import Department, DepartmentPermission, DepartmentShop, Permission, PlatformConfig, Role, RolePermission, Shop, Org, User, UserRole, UserShop
from app.routers.base import BaseRouter
from app.schemas.common import ok
from app.schemas.rbac import (
    AssignIdsIn, AssignPermissionsIn, BootstrapIn, DepartmentIn, DepartmentOut, LoginIn,
    LoginOut, ManagerCandidateOut, PermissionOut, PlatformConfigIn, RegisterIn, ResetPasswordIn,
    RoleIn, RoleOut, ShopIn, ShopOut, OrgIn, OrgOut, UserIn, UserOut, UserUpdateIn,
)
from app.services.rbac import RbacService, bootstrap, create_org, register_user, touch_login
from app.services.rbac_seed import PERMISSION_MODULES
from app.utils.rbac import Principal, get_principal, require_permission, resolve_principal
from app.utils.security import create_access_token, verify_password


MANAGE = require_permission("system:org:roleManage")


def _permission_out(item: Permission) -> dict:
    return {**PermissionOut.model_validate(item).model_dump(),
            "module_name": item.module_name or PERMISSION_MODULES.get(item.perm_key, "未分类")}


def _commit(db: Session) -> None:
    """提交当前请求事务；提交失败则回滚，避免脏事务进入连接池。"""
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise


def _service(db: Session, principal: Principal) -> RbacService:
    """用当前登录人的租户上下文构造服务，保证数据操作租户隔离。"""
    return RbacService(db, principal.org_id, principal.user_id)


def _shop_out(item: Shop, db: Session) -> dict:
    """组装店铺及其全部分管部门，供页面展示一店多人关系。"""
    dept_ids = db.scalars(select(DepartmentShop.dept_id).where(
        DepartmentShop.org_id == item.org_id, DepartmentShop.shop_id == item.id,
        DepartmentShop.deleted.is_(False),
    ).order_by(DepartmentShop.dept_id)).all()
    names = dict(db.execute(select(Department.id, Department.dept_name).where(
        Department.id.in_(dept_ids), Department.deleted.is_(False)
    )).all()) if dept_ids else {}
    return {**ShopOut.model_validate(item).model_dump(),
            "dept_ids": list(dept_ids), "dept_names": [names[i] for i in dept_ids if i in names]}


def _role_out(role: Role, db: Session) -> dict:
    """组装角色及其有效权限编码，供管理页面直接展示。"""
    keys = db.scalars(
        select(Permission.perm_key)
        .join(RolePermission, RolePermission.perm_id == Permission.id)
        .where(RolePermission.role_id == role.id, RolePermission.deleted.is_(False))
    ).all()
    return {**RoleOut.model_validate(role).model_dump(), "permission_keys": list(keys)}


def _user_out(user: User, db: Session) -> dict:
    """组装用户、角色和店铺可见范围，供管理页面直接展示。"""
    roles = db.execute(
        select(Role.role_code, Role.role_name).join(UserRole, UserRole.role_id == Role.id)
        .where(UserRole.user_id == user.id, UserRole.deleted.is_(False))
    ).all()
    shops = db.scalars(
        select(UserShop.shop_id).where(UserShop.user_id == user.id, UserShop.deleted.is_(False))
    ).all()
    return {**UserOut.model_validate(user).model_dump(),
            "role_codes": [code for code, _ in roles],
            "role_names": [name for _, name in roles], "shop_ids": list(shops)}


def _department_out(department: Department, db: Session) -> dict:
    """组装部门及其权限配置；配置不直接授予部门成员。"""
    keys = db.scalars(
        select(Permission.perm_key)
        .join(DepartmentPermission, DepartmentPermission.perm_id == Permission.id)
        .where(DepartmentPermission.dept_id == department.id,
               DepartmentPermission.org_id == department.org_id,
               DepartmentPermission.deleted.is_(False))
        .order_by(Permission.perm_key)
    ).all()
    shop_ids = db.scalars(select(DepartmentShop.shop_id).where(
        DepartmentShop.org_id == department.org_id, DepartmentShop.dept_id == department.id,
        DepartmentShop.deleted.is_(False),
    )).all()
    # 负责人状态由用户表实时判定：即使触发器未来漏清空，也不会对外展示离职者为有效负责人。
    if department.manager_id is None:
        manager_status = "UNASSIGNED"
    else:
        manager_status = db.scalar(select(User.status).where(
            User.id == department.manager_id, User.org_id == department.org_id,
            User.deleted.is_(False),
        )) or "DISABLED"
    return {**DepartmentOut.model_validate(department).model_dump(),
            "manager_status": manager_status,
            "permission_keys": list(keys), "shop_ids": list(shop_ids)}


class RbacRouter(BaseRouter):
    """集中注册 RBAC 模块接口，并将 OpenAPI 描述紧贴处理函数。"""

    tags = ["RBAC 权限管理"]

    def _register_routes(self) -> None:
        """参照 BaseRouter 模式注册所有接口及其 Swagger 元数据。"""
        # 认证：匿名访问，其他接口依赖 JWT 和 system:org:roleManage 权限。
        self.router.post("/auth/bootstrap", status_code=status.HTTP_201_CREATED,
                         summary="初始化首个租户管理员",
                         description="仅在系统没有任何用户时可调用；创建租户、角色、权限和超级管理员。", tags=["认证"])(self.bootstrap_admin)
        self.router.post("/auth/login", response_model=None, summary="租户用户登录",
                         description="校验租户编码、用户名和密码，成功后签发 JWT 访问令牌。", tags=["认证"])(self.login)
        self.router.post("/auth/register", status_code=status.HTTP_201_CREATED, summary="注册租户用户",
                         description="在已有租户中创建待启用账号；管理员启用并分配角色后才可登录。", tags=["认证"])(self.register)
        self.router.get("/auth/me", summary="获取当前登录人",
                        description="从 Bearer Token 解析用户，并实时返回角色、权限和数据范围。", tags=["认证"])(self.me)

        # 租户和全局权限目录。
        self.router.get("/system/orgs", summary="查询租户列表",
                        description="需要系统管理权限；仅返回未逻辑删除的租户。", tags=["租户管理"])(self.list_orgs)
        self.router.post("/system/orgs", status_code=status.HTTP_201_CREATED, summary="创建租户",
                         description="创建租户并自动初始化标准角色及最小权限关联。", tags=["租户管理"])(self.add_org)
        self.router.patch("/system/orgs/{org_id}", summary="更新租户",
                          description="修改指定租户资料与状态；租户不存在时返回 404。", tags=["租户管理"])(self.edit_org)
        self.router.get("/rbac/permissions", summary="查询权限目录",
                        description="返回全局权限编码目录，供角色授权页面选择。", tags=["权限管理"])(self.list_permissions)
        self.router.get("/rbac/my-permissions", summary="查询我的权限模块",
                        description="只返回当前用户实际拥有的权限及其 Agent 模块分类。", tags=["权限管理"])(self.my_permissions)

        # 当前租户下的部门管理。
        self.router.get("/rbac/departments", summary="查询当前租户部门",
                        description="按当前登录人的租户上下文过滤，不能跨租户读取。", tags=["部门管理"])(self.list_departments)
        self.router.post("/rbac/departments", status_code=status.HTTP_201_CREATED, summary="创建部门",
                         description="在当前租户创建部门，可指定有效的上级部门。", tags=["部门管理"])(self.add_department)
        self.router.get("/rbac/departments/manager-candidates", summary="查询可选部门负责人",
                        description="返回当前租户启用状态的用户，供部门负责人下拉选择；离职/停用用户不在列表中。",
                        tags=["部门管理"])(self.list_manager_candidates)
        self.router.patch("/rbac/departments/{record_id}", summary="更新部门",
                          description="只允许修改当前租户内的部门。", tags=["部门管理"])(self.edit_department)
        self.router.delete("/rbac/departments/{record_id}", summary="删除部门",
                           description="对当前租户部门执行逻辑删除；不存在时返回 404。", tags=["部门管理"])(self.delete_department)
        self.router.put("/rbac/departments/{record_id}/permissions", summary="配置部门权限",
                        description="记录部门可配置的权限清单；用户有效权限仍由角色决定。", tags=["部门管理"])(self.set_department_permissions)
        self.router.put("/rbac/departments/{record_id}/shops", summary="分配部门店铺",
                        description="以完整店铺列表替换该部门的店铺归属，店铺只属于一个部门。", tags=["部门管理"])(self.set_department_shops)

        # 角色和角色授权。
        self.router.get("/rbac/roles", summary="查询当前租户角色",
                        description="返回角色信息及每个角色已拥有的权限编码。", tags=["角色管理"])(self.list_roles)
        self.router.post("/rbac/roles", status_code=status.HTTP_201_CREATED, summary="创建角色",
                         description="在当前租户创建角色，角色编码在该租户内唯一。", tags=["角色管理"])(self.add_role)
        self.router.patch("/rbac/roles/{record_id}", summary="更新角色",
                          description="只允许编辑当前租户角色，不能通过 ID 修改其他租户角色。", tags=["角色管理"])(self.edit_role)
        self.router.delete("/rbac/roles/{record_id}", summary="删除角色",
                           description="逻辑删除未被有效用户使用的普通角色；超级管理员角色不可删除。", tags=["角色管理"])(self.delete_role)
        self.router.put("/rbac/roles/{record_id}/permissions", summary="覆盖设置角色权限",
                        description="以提交的权限 ID 集合替换角色已有授权，并校验权限有效。", tags=["角色管理"])(self.set_role_permissions)

        # 用户、角色分配和店铺数据范围。
        self.router.get("/rbac/users", summary="查询当前租户用户",
                        description="返回用户基本资料、角色编码与授权店铺范围。", tags=["用户管理"])(self.list_users)
        self.router.post("/rbac/users", status_code=status.HTTP_201_CREATED, summary="创建用户",
                         description="在当前租户创建用户，明文密码仅用于生成 Argon2id 摘要。", tags=["用户管理"])(self.add_user)
        self.router.patch("/rbac/users/{record_id}", summary="更新用户",
                          description="局部更新当前租户用户，未提交字段不覆盖。", tags=["用户管理"])(self.edit_user)
        self.router.delete("/rbac/users/{record_id}", summary="删除用户",
                           description="逻辑删除当前租户用户并撤销角色及店铺关联；禁止删除自己或最后一名超级管理员。", tags=["用户管理"])(self.delete_user)
        self.router.put("/rbac/users/{record_id}/roles", summary="覆盖设置用户角色",
                        description="以提交的角色 ID 集合替换用户角色，并校验角色属于当前租户。", tags=["用户管理"])(self.set_user_roles)
        self.router.put("/rbac/users/{record_id}/shops", summary="覆盖设置用户店铺范围",
                        description="以提交的店铺 ID 集合替换可访问店铺，并校验店铺属于当前租户。", tags=["用户管理"])(self.set_user_shops)
        self.router.post("/rbac/users/{record_id}/reset-password", summary="重置用户密码",
                         description="为当前租户用户重新生成 Argon2id 密码摘要，不保存明文。", tags=["用户管理"])(self.reset_password)

        # 店铺与跨境平台 API 连接配置。
        self.router.get("/rbac/shops", summary="查询当前租户店铺",
                        description="返回当前租户下未逻辑删除的店铺。", tags=["店铺管理"])(self.list_shops)
        self.router.post("/rbac/shops", status_code=status.HTTP_201_CREATED, summary="创建店铺",
                         description="在当前租户接入店铺，店铺编码在租户内唯一。", tags=["店铺管理"])(self.add_shop)
        self.router.patch("/rbac/shops/{record_id}", summary="更新店铺",
                          description="只允许修改当前租户店铺。", tags=["店铺管理"])(self.edit_shop)
        self.router.get("/rbac/platform-configs", summary="查询平台连接配置",
                        description="返回当前租户店铺的平台连接配置；敏感凭据不会明文返回。", tags=["平台配置"])(self.list_platform_configs)
        self.router.post("/rbac/platform-configs", status_code=status.HTTP_201_CREATED, summary="创建平台连接配置",
                         description="保存平台 API 连接信息，敏感凭据加密后写入数据库。", tags=["平台配置"])(self.add_platform_config)
        self.router.patch("/rbac/platform-configs/{record_id}", summary="更新平台连接配置",
                          description="更新当前租户配置，敏感字段始终加密存储。", tags=["平台配置"])(self.edit_platform_config)

    def bootstrap_admin(self, payload: BootstrapIn, db: Session = Depends(get_db)) -> dict:
        """初始化首个管理员：阻止重复初始化，成功后返回用户 ID。"""
        user = bootstrap(db, **payload.model_dump())
        _commit(db)
        return ok({"user_id": user.id, "message": "首个租户和超级管理员已创建"})

    def login(self, payload: LoginIn, db: Session = Depends(get_db)) -> dict:
        """验证租户用户身份，签发包含租户和角色声明的 JWT。"""
        org = db.scalar(select(Org).where(Org.org_code == payload.org_code, Org.deleted.is_(False)))
        if org is None or org.status != "ACTIVE":
            raise UnauthorizedException("租户不存在或不可用")
        user = db.scalar(select(User).where(User.org_id == org.id, User.username == payload.username,
                                            User.deleted.is_(False), User.status == "ENABLED"))
        if user is None or not verify_password(payload.password, user.password_hash):
            raise UnauthorizedException("用户名或密码错误")
        touch_login(user)
        principal = resolve_principal({"user_id": str(user.id)}, db)
        token = create_access_token(str(user.id), {"org_id": user.org_id, "roles": sorted(principal.role_codes)})
        _commit(db)
        return ok(LoginOut(access_token=token).model_dump())

    def register(self, payload: RegisterIn, db: Session = Depends(get_db)) -> dict:
        """自助注册已有租户的待启用账号，不授予任何角色或权限。"""
        if payload.password != payload.confirm_password:
            raise ValidationException("两次输入的密码不一致")
        values = payload.model_dump(exclude={"org_code", "confirm_password"})
        try:
            register_user(db, payload.org_code, values)
            _commit(db)
        except IntegrityError as exc:
            db.rollback()
            raise ConflictException("用户名或邮箱已存在") from exc
        return ok({"message": "注册成功，请等待管理员启用账号并分配角色"})

    def me(self, principal: Principal = Depends(get_principal)) -> dict:
        """读取经实时权限解析后的当前用户身份、角色和权限集合。"""
        return ok({"user_id": principal.user_id, "org_id": principal.org_id, "username": principal.username,
                   "roles": sorted(principal.role_codes), "permissions": sorted(principal.permission_keys), "data_scope": principal.data_scope})

    def list_orgs(self, _: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """列出所有有效租户，仅系统管理权限可访问。"""
        return ok([OrgOut.model_validate(item).model_dump() for item in db.scalars(select(Org).where(Org.deleted.is_(False)).order_by(Org.id)).all()])

    def add_org(self, payload: OrgIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """创建租户并生成预置角色和权限关联。"""
        item = create_org(db, payload.model_dump(), principal.user_id)
        _commit(db)
        return ok(OrgOut.model_validate(item).model_dump())

    def edit_org(self, org_id: int, payload: OrgIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """更新租户资料并记录最后修改人。"""
        item = db.scalar(select(Org).where(Org.id == org_id, Org.deleted.is_(False)))
        if item is None:
            raise NotFoundException()
        for key, value in payload.model_dump().items():
            setattr(item, key, value)
        item.updated_by = principal.user_id
        _commit(db)
        return ok(OrgOut.model_validate(item).model_dump())

    def list_permissions(self, _: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """列出可用于角色授权的全局权限目录。"""
        return ok([_permission_out(item) for item in db.scalars(select(Permission).where(Permission.deleted.is_(False)).order_by(Permission.perm_key)).all()])

    def my_permissions(self, principal: Principal = Depends(get_principal), db: Session = Depends(get_db)) -> dict:
        """登录用户只读取本人当前有效权限的名称、编码和模块。"""
        items = db.scalars(select(Permission).where(
            Permission.perm_key.in_(principal.permission_keys), Permission.deleted.is_(False),
            Permission.status == "ENABLED",
        ).order_by(Permission.perm_key)).all()
        return ok([_permission_out(item) for item in items])

    def list_departments(self, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """查询当前租户部门。"""
        items = _service(db, principal)._repo(Department).list()
        return ok([_department_out(item, db) for item in sorted(items, key=lambda item: (item.sort, item.id))])

    def list_manager_candidates(self, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """查询可作为部门负责人的启用用户，附带所属部门名称。"""
        rows = db.execute(
            select(User, Department.dept_name)
            .outerjoin(Department, Department.id == User.dept_id)
            .where(User.org_id == principal.org_id, User.deleted.is_(False),
                   User.status == "ENABLED")
            .order_by(User.dept_id, User.id)
        ).all()
        return ok([
            {**ManagerCandidateOut.model_validate(user).model_dump(), "dept_name": dept_name}
            for user, dept_name in rows
        ])

    def add_department(self, payload: DepartmentIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """创建当前租户部门。"""
        item = _service(db, principal).create_department(payload.model_dump())
        _commit(db)
        return ok(_department_out(item, db))

    def edit_department(self, record_id: int, payload: DepartmentIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """更新当前租户部门。"""
        item = _service(db, principal).update_department(record_id, payload.model_dump())
        _commit(db)
        return ok(_department_out(item, db))

    def delete_department(self, record_id: int, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """逻辑删除当前租户部门。"""
        _service(db, principal).delete_department(record_id)
        _commit(db)
        return ok(message="删除成功")

    def set_department_permissions(self, record_id: int, payload: AssignPermissionsIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """替换部门权限配置，不改变成员的登录有效权限。"""
        _service(db, principal).assign_department_permissions(record_id, payload.permission_ids)
        _commit(db)
        return ok(message="部门权限配置已保存")

    def set_department_shops(self, record_id: int, payload: AssignIdsIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """设置本部门分管的店铺；不影响其他部门对同一店铺的管理关系。"""
        _service(db, principal).assign_department_shops(record_id, payload.ids)
        _commit(db)
        return ok(message="店铺分配成功")

    def list_roles(self, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """查询当前租户角色及其权限编码。"""
        items = _service(db, principal)._repo(Role).list()
        return ok([_role_out(item, db) for item in sorted(items, key=lambda item: (item.sort, item.id))])

    def add_role(self, payload: RoleIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """创建当前租户角色。"""
        item = _service(db, principal).create_role(payload.model_dump())
        _commit(db)
        return ok(_role_out(item, db))

    def edit_role(self, record_id: int, payload: RoleIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """更新当前租户角色。"""
        item = _service(db, principal).update_role(record_id, payload.model_dump())
        _commit(db)
        return ok(_role_out(item, db))

    def delete_role(self, record_id: int, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """删除角色前检查用户关联，避免产生悬空授权。"""
        _service(db, principal).delete_role(record_id)
        _commit(db)
        return ok(message="删除成功")


    def set_role_permissions(self, record_id: int, payload: AssignPermissionsIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """以完整列表替换角色的权限关联。"""
        _service(db, principal).assign_role_permissions(record_id, payload.permission_ids)
        _commit(db)
        return ok(message="权限分配成功")

    def list_users(self, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """查询当前租户用户及授权范围。"""
        return ok([_user_out(item, db) for item in _service(db, principal)._repo(User).list()])

    def add_user(self, payload: UserIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """创建当前租户用户并安全哈希密码。"""
        item = _service(db, principal).create_user(payload.model_dump())
        _commit(db)
        return ok(_user_out(item, db))

    def edit_user(self, record_id: int, payload: UserUpdateIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """局部更新当前租户用户。"""
        try:
            item = _service(db, principal).update_user(record_id, payload.model_dump(exclude_unset=True))
            _commit(db)
        except IntegrityError as exc:
            db.rollback()
            raise ConflictException("邮箱已被当前租户其他用户使用") from exc
        return ok(_user_out(item, db))

    def delete_user(self, record_id: int, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """删除当前租户用户并撤销关联授权。"""
        _service(db, principal).delete_user(record_id)
        _commit(db)
        return ok(message="删除成功")


    def set_user_roles(self, record_id: int, payload: AssignIdsIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """以完整列表替换用户角色。"""
        _service(db, principal).assign_user_roles(record_id, payload.ids)
        _commit(db)
        return ok(message="角色分配成功")

    def set_user_shops(self, record_id: int, payload: AssignIdsIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """以完整列表替换用户可访问店铺。"""
        _service(db, principal).assign_user_shops(record_id, payload.ids)
        _commit(db)
        return ok(message="店铺范围分配成功")

    def reset_password(self, record_id: int, payload: ResetPasswordIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """重置当前租户用户密码。"""
        _service(db, principal).reset_password(record_id, payload.password)
        _commit(db)
        return ok(message="密码已重置")

    def list_shops(self, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """查询当前租户店铺及其分管部门。"""
        return ok([_shop_out(item, db) for item in _service(db, principal)._repo(Shop).list()])

    def add_shop(self, payload: ShopIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """创建当前租户店铺。"""
        item = _service(db, principal).create_shop(payload.model_dump())
        _commit(db)
        return ok(ShopOut.model_validate(item).model_dump())

    def edit_shop(self, record_id: int, payload: ShopIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """更新当前租户店铺。"""
        item = _service(db, principal).update_shop(record_id, payload.model_dump())
        _commit(db)
        return ok(ShopOut.model_validate(item).model_dump())

    def list_platform_configs(self, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """查询当前租户平台连接配置并脱敏输出。"""
        return ok([RbacService.config_out(item) for item in _service(db, principal)._repo(PlatformConfig).list()])

    def add_platform_config(self, payload: PlatformConfigIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """创建当前租户店铺的平台连接配置。"""
        item = _service(db, principal).save_platform_config(None, payload.model_dump())
        _commit(db)
        return ok(RbacService.config_out(item))

    def edit_platform_config(self, record_id: int, payload: PlatformConfigIn, principal: Principal = Depends(MANAGE), db: Session = Depends(get_db)) -> dict:
        """更新当前租户的平台连接配置。"""
        item = _service(db, principal).save_platform_config(record_id, payload.model_dump())
        _commit(db)
        return ok(RbacService.config_out(item))


# 保持 app.routers.register_routes 的现有导入方式。
router = RbacRouter().router
