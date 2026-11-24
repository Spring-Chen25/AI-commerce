"""RBAC 核心规则：初始化、租户隔离、授权替换与凭据脱敏。"""

from sqlalchemy import create_engine, select
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import sessionmaker
from fastapi.testclient import TestClient

from app.database import Base
from app.exceptions import ConflictException, NotFoundException, ValidationException
from app.models import rbac  # noqa: F401  确保 RBAC 表注册到 metadata
from app.models.rbac import Department, Permission, Role, RolePermission, Shop, User, UserRole
from app.services.rbac import RbacService, bootstrap
from app.utils.rbac import resolve_principal


def make_session():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    return sessionmaker(bind=engine)()


def test_bootstrap_creates_catalog_roles_and_super_admin():
    db = make_session()
    user = bootstrap(db, "demo", "演示租户", "admin", "safe-password", "管理员")
    db.commit()
    assert db.scalar(select(User).where(User.id == user.id)).org_id == user.org_id
    assert len(db.scalars(select(Role).where(Role.org_id == user.org_id)).all()) == 20
    assert len(db.scalars(select(Permission)).all()) == 29
    assert db.scalar(select(UserRole).where(UserRole.user_id == user.id)) is not None
    super_role = db.scalar(select(Role).where(Role.org_id == user.org_id, Role.role_code == "SUPER_ADMIN"))
    assigned_keys = set(db.scalars(
        select(Permission.perm_key).join(RolePermission, RolePermission.perm_id == Permission.id)
        .where(RolePermission.role_id == super_role.id)
    ).all())
    assert assigned_keys == {"system:org:roleManage"}
    assert len(resolve_principal({"user_id": str(user.id)}, db).permission_keys) == 29


def test_service_rejects_cross_org_role_assignment():
    db = make_session()
    first = bootstrap(db, "a", "租户 A", "admin-a", "safe-password", "管理员 A")
    db.commit()
    from app.models.rbac import Org, Role
    other = Org(org_code="b", org_name="租户 B")
    db.add(other)
    db.flush()
    foreign_role = Role(org_id=other.id, role_code="FOREIGN", role_name="跨租户角色")
    db.add(foreign_role)
    db.commit()
    service = RbacService(db, first.org_id, first.id)
    try:
        service.assign_user_roles(first.id, [foreign_role.id])
    except NotFoundException:
        pass
    else:
        raise AssertionError("跨租户角色不应能分配给当前租户用户")


def test_user_role_names_and_safe_deletion():
    """列表显示角色名称；删除用户撤销授权，已分配角色不能删除。"""
    db = make_session()
    admin = bootstrap(db, "demo", "演示租户", "admin", "safe-password", "管理员")
    service = RbacService(db, admin.org_id, admin.id)
    role = db.scalar(select(Role).where(Role.org_id == admin.org_id, Role.role_code == "GOODS_OPER"))
    member = service.create_user({
        "username": "operator", "password": "safe-password", "real_name": "运营专员",
        "status": "ENABLED", "data_scope": "SELF",
    })
    service.assign_user_roles(member.id, [role.id])
    from app.routers.rbac import _user_out
    assert _user_out(member, db)["role_names"] == [role.role_name]
    try:
        service.delete_role(role.id)
    except ConflictException:
        pass
    else:
        raise AssertionError("已分配给用户的角色不应删除")
    service.delete_user(member.id)
    assert member.deleted is True
    assert db.scalar(select(UserRole).where(UserRole.user_id == member.id)).deleted is True
    service.delete_role(role.id)
    assert role.deleted is True
    try:
        service.delete_user(admin.id)
    except ValidationException:
        pass
    else:
        raise AssertionError("不能删除当前登录用户")


def test_department_shop_assignment_is_many_to_many():
    """一个店铺可被多个部门分管；给 B 分配不会夺走 A 的分管关系。"""
    from app.models.rbac import DepartmentShop
    db = make_session()
    admin = bootstrap(db, "demo", "演示租户", "admin", "safe-password", "管理员")
    service = RbacService(db, admin.org_id, admin.id)
    first = service.create_department({"parent_id": 0, "dept_name": "运营部", "dept_code": "OPS"})
    second = service.create_department({"parent_id": 0, "dept_name": "客服部", "dept_code": "CS"})
    shop = service.create_shop({"shop_name": "美国站", "shop_code": "US", "platform": "AMAZON", "dept_id": first.id})

    # 部门 A 分管店铺
    service.assign_department_shops(first.id, [shop.id])
    assert db.scalar(select(DepartmentShop).where(
        DepartmentShop.dept_id == first.id, DepartmentShop.shop_id == shop.id)) is not None
    assert shop.dept_id == first.id  # 主归属字段不被分配逻辑改写

    # 部门 B 也分管同一店铺：A 的关系不受影响
    service.assign_department_shops(second.id, [shop.id])
    rel_depts = set(db.scalars(select(DepartmentShop.dept_id).where(
        DepartmentShop.shop_id == shop.id, DepartmentShop.deleted.is_(False))).all())
    assert rel_depts == {first.id, second.id}

    # B 取消分管：A 仍然保留
    service.assign_department_shops(second.id, [])
    rel_depts = set(db.scalars(select(DepartmentShop.dept_id).where(
        DepartmentShop.shop_id == shop.id, DepartmentShop.deleted.is_(False))).all())
    assert rel_depts == {first.id}


def test_bootstrap_login_and_me_http_flow(tmp_path):
    """验证前端实际依赖的初始化、JWT 登录和当前用户链路。"""
    from app import database
    from main import app

    previous_urls = dict(database._DB_URLS)
    previous_engines = dict(database._ENGINES)
    previous_factories = dict(database._FACTORIES)
    test_url = f"sqlite:///{tmp_path / 'rbac-http.db'}"
    try:
        database._DB_URLS["default"] = test_url
        database._ENGINES.clear()
        database._FACTORIES.clear()
        Base.metadata.create_all(create_engine(test_url))
        client = TestClient(app, raise_server_exceptions=True)
        bootstrap_response = client.post("/api/v1/auth/bootstrap", json={
            "org_code": "HTTP_TEST", "org_name": "HTTP 测试租户",
            "username": "admin", "password": "safe-password", "real_name": "管理员",
        })
        assert bootstrap_response.status_code == 201
        login_response = client.post("/api/v1/auth/login", json={
            "org_code": "HTTP_TEST", "username": "admin", "password": "safe-password",
        })
        assert login_response.status_code == 200
        token = login_response.json()["data"]["access_token"]
        me_response = client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
        assert me_response.status_code == 200
        assert me_response.json()["data"]["username"] == "admin"
        permissions_response = client.get("/api/v1/rbac/my-permissions", headers={"Authorization": f"Bearer {token}"})
        assert permissions_response.status_code == 200
        assert len(permissions_response.json()["data"]) == 29
        assert any(item["module_name"] == "智能客服 Agent" for item in permissions_response.json()["data"])

        registration = {
            "org_code": "HTTP_TEST", "username": "new_member", "real_name": "新成员",
            "email": "", "phone": "", "password": "safe-password", "confirm_password": "safe-password",
        }
        register_response = client.post("/api/v1/auth/register", json=registration)
        assert register_response.status_code == 201
        with sessionmaker(bind=create_engine(test_url))() as db:
            member = db.scalar(select(User).where(User.username == "new_member"))
            assert member.status == "DISABLED"
            assert member.org_id == int(me_response.json()["data"]["org_id"])
            assert member.email is None
            assert member.password_hash != registration["password"]
            assert db.scalar(select(UserRole).where(UserRole.user_id == member.id)) is None
        assert client.post("/api/v1/auth/register", json=registration).status_code == 409
        assert client.post("/api/v1/auth/login", json={
            "org_code": "HTTP_TEST", "username": "new_member", "password": "safe-password",
        }).status_code == 401

        # 旧数据中可能已有空字符串邮箱；编辑另一个用户时不应再写入 "" 并触发唯一约束。
        with sessionmaker(bind=create_engine(test_url))() as db:
            db.add(User(org_id=member.org_id, username="legacy", real_name="旧账号",
                        password_hash="unused", email=""))
            db.commit()
        update_response = client.patch(
            f"/api/v1/rbac/users/{member.id}",
            json={"real_name": "新成员", "email": "", "phone": "", "status": "ENABLED"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert update_response.status_code == 200
        with sessionmaker(bind=create_engine(test_url))() as db:
            updated = db.get(User, member.id)
            assert updated.status == "ENABLED"
            assert updated.email is None
            assert updated.phone is None
    finally:
        database._DB_URLS.clear()
        database._DB_URLS.update(previous_urls)
        database._ENGINES.clear()
        database._ENGINES.update(previous_engines)
        database._FACTORIES.clear()
        database._FACTORIES.update(previous_factories)


def test_register_reports_database_unavailable():
    """数据库断开时注册接口返回可读的 503，而不是裸异常堆栈。"""
    from app.database import get_db
    from main import app

    def offline_db():
        raise OperationalError("SELECT 1", {}, RuntimeError("offline"))

    previous = app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db] = offline_db
    try:
        response = TestClient(app, raise_server_exceptions=False).post("/api/v1/auth/register", json={
            "org_code": "DEMO", "username": "new_member", "real_name": "新成员",
            "password": "safe-password", "confirm_password": "safe-password",
        })
        assert response.status_code == 503
        assert response.json()["message"] == "数据库暂不可用，请检查当前数据库连接和库是否存在"
    finally:
        if previous is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = previous
