"""RBAC 管理接口的输入输出模型。"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class LoginIn(BaseModel):
    org_code: str = Field(min_length=1, max_length=64)
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=8, max_length=128)


class LoginOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class RegisterIn(BaseModel):
    org_code: str = Field(min_length=1, max_length=64)
    username: str = Field(min_length=1, max_length=64)
    real_name: str = Field(min_length=1, max_length=64)
    email: str | None = Field(default=None, max_length=128)
    phone: str | None = Field(default=None, max_length=32)
    password: str = Field(min_length=8, max_length=128)
    confirm_password: str = Field(min_length=8, max_length=128)


class BootstrapIn(BaseModel):
    org_code: str = Field(min_length=1, max_length=64)
    org_name: str = Field(min_length=1, max_length=128)
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=8, max_length=128)
    real_name: str = Field(min_length=1, max_length=64)


class OrgIn(BaseModel):
    org_code: str = Field(min_length=1, max_length=64)
    org_name: str = Field(min_length=1, max_length=128)
    domain: str | None = Field(default=None, max_length=128)
    package_code: str | None = Field(default=None, max_length=64)
    data_region: str | None = Field(default=None, max_length=64)
    status: str = Field(default="ACTIVE", pattern="^(PENDING|ACTIVE|SUSPENDED|EXPIRED)$")
    expire_at: datetime | None = None


class OrgOut(OrgIn, ORMModel):
    id: int


class DepartmentIn(BaseModel):
    parent_id: int = Field(default=0, ge=0)
    dept_name: str = Field(min_length=1, max_length=128)
    dept_code: str = Field(min_length=1, max_length=64)
    manager_id: int | None = Field(default=None, ge=1)
    manager_name: str | None = Field(default=None, max_length=64)
    phone: str | None = Field(default=None, max_length=32)
    email: str | None = Field(default=None, max_length=128)
    sort: int = Field(default=0, ge=0)
    status: str = Field(default="ENABLED", pattern="^(ENABLED|DISABLED)$")


class DepartmentOut(DepartmentIn, ORMModel):
    id: int
    org_id: int
    # 负责人实时状态：UNASSIGNED / ENABLED / DISABLED，供前端展示"待指派"或"已停用"。
    manager_status: str = "UNASSIGNED"
    permission_keys: list[str] = Field(default_factory=list)
    shop_ids: list[int] = Field(default_factory=list)


class ManagerCandidateOut(ORMModel):
    id: int
    username: str
    real_name: str
    dept_id: int | None
    dept_name: str | None = None
    status: str


class RoleIn(BaseModel):
    role_name: str = Field(min_length=1, max_length=64)
    role_code: str = Field(min_length=1, max_length=64)
    description: str | None = Field(default=None, max_length=512)
    data_scope: str = Field(default="SELF", pattern="^(SELF|DEPT|DEPT_AND_CHILDREN|ORG|ALL)$")
    sort: int = Field(default=0, ge=0)
    status: str = Field(default="ENABLED", pattern="^(ENABLED|DISABLED)$")


class RoleOut(RoleIn, ORMModel):
    id: int
    org_id: int
    permission_keys: list[str] = []


class PermissionOut(ORMModel):
    id: int
    perm_name: str
    perm_key: str
    description: str | None
    perm_type: str
    status: str
    module_name: str = "未分类"


class AssignPermissionsIn(BaseModel):
    permission_ids: list[int] = Field(default_factory=list)


class UserIn(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=8, max_length=128)
    real_name: str = Field(min_length=1, max_length=64)
    dept_id: int | None = None
    email: str | None = Field(default=None, max_length=128)
    phone: str | None = Field(default=None, max_length=32)
    data_scope: str = Field(default="SELF", pattern="^(SELF|DEPT|DEPT_AND_CHILDREN|ORG|ALL)$")
    status: str = Field(default="ENABLED", pattern="^(ENABLED|DISABLED)$")


class UserUpdateIn(BaseModel):
    real_name: str | None = Field(default=None, min_length=1, max_length=64)
    dept_id: int | None = None
    email: str | None = Field(default=None, max_length=128)
    phone: str | None = Field(default=None, max_length=32)
    data_scope: str | None = Field(default=None, pattern="^(SELF|DEPT|DEPT_AND_CHILDREN|ORG|ALL)$")
    status: str | None = Field(default=None, pattern="^(ENABLED|DISABLED)$")


class UserOut(ORMModel):
    id: int
    org_id: int
    dept_id: int | None
    username: str
    real_name: str
    email: str | None
    phone: str | None
    data_scope: str
    status: str
    last_login_at: datetime | None
    role_codes: list[str] = []
    role_names: list[str] = []
    shop_ids: list[int] = []


class AssignIdsIn(BaseModel):
    ids: list[int] = Field(default_factory=list)


class ResetPasswordIn(BaseModel):
    password: str = Field(min_length=8, max_length=128)


class ShopIn(BaseModel):
    dept_id: int | None = None
    shop_name: str = Field(min_length=1, max_length=128)
    shop_code: str = Field(min_length=1, max_length=64)
    platform: str = Field(min_length=1, max_length=32)
    status: str = Field(default="ENABLED", pattern="^(ENABLED|DISABLED)$")


class ShopOut(ShopIn, ORMModel):
    id: int
    org_id: int


class PlatformConfigIn(BaseModel):
    shop_id: int
    platform: str = Field(min_length=1, max_length=32)
    api_key: str | None = Field(default=None, max_length=2048)
    api_secret: str | None = Field(default=None, max_length=2048)
    access_token: str | None = Field(default=None, max_length=4096)
    api_base_url: str | None = Field(default=None, max_length=512)
    callback_url: str | None = Field(default=None, max_length=512)
    status: str = Field(default="ENABLED", pattern="^(ENABLED|DISABLED)$")


class PlatformConfigOut(ORMModel):
    id: int
    org_id: int
    shop_id: int
    platform: str
    api_key_masked: str | None
    api_secret_masked: str | None
    access_token_masked: str | None
    api_base_url: str | None
    callback_url: str | None
    status: str
