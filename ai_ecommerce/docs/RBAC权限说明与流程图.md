# RBAC 权限使用说明

本文说明当前跨境电商平台的认证、授权、组织隔离和店铺数据范围实现。接口基地址为 `/api/v1`；除初始化和登录外，所有 RBAC 管理接口都要求携带 `Authorization: Bearer <access_token>`。

## 1. 权限模型

系统采用“用户 → 角色 → 权限”的 RBAC 模型，并在用户、角色、部门、店铺和平台配置等业务数据上强制带入组织 ID。

| 对象 | 表 | 作用 |
| --- | --- | --- |
| 组织 | `sys_org` | 数据隔离边界；组织失效后不能登录 |
| 用户 | `sys_user` | 登录主体，归属一个组织，可关联部门 |
| 角色 | `sys_role` | 同一组织内定义职责与数据范围 |
| 权限 | `sys_permission` | 全局权限编码目录，例如 `system:tenant:roleManage` |
| 用户角色 | `sys_user_role` | 用户与角色的多对多关系 |
| 角色权限 | `sys_role_permission` | 角色与权限的多对多关系 |
| 店铺范围 | `sys_user_shop` | 用户可访问店铺的额外数据范围 |
| 部门店铺归属 | `biz_department_shop` | 多对多：一个部门可管多店，一个店可被多个部门管理 |

`SUPER_ADMIN` 是特殊角色：它可访问所有已启用权限。普通角色仅获得 `sys_role_permission` 中明确关联的权限，遵循最小权限原则。

```mermaid
erDiagram
    SYS_ORG ||--o{ SYS_USER : owns
    SYS_ORG ||--o{ SYS_ROLE : owns
    SYS_ORG ||--o{ BIZ_DEPARTMENT : owns
    SYS_ORG ||--o{ BIZ_SHOP : owns
    SYS_USER ||--o{ SYS_USER_ROLE : has
    SYS_ROLE ||--o{ SYS_USER_ROLE : assigned_to
    SYS_ROLE ||--o{ SYS_ROLE_PERMISSION : grants
    SYS_PERMISSION ||--o{ SYS_ROLE_PERMISSION : included_by
    SYS_USER ||--o{ SYS_USER_SHOP : scoped_to
    BIZ_SHOP ||--o{ SYS_USER_SHOP : visible_to
```

## 2. 登录与鉴权流程

1. 管理端调用 `POST /auth/login`，提交 `org_code`、`username`、`password`。
2. 后端确认组织、用户均处于 `ACTIVE/ENABLED` 状态，并以 Argon2id 校验密码摘要。
3. 后端实时读取用户角色及权限，签发 JWT；Token 仅保存用户 ID、组织 ID 和角色快照。
4. 受保护接口通过 `get_principal` 解析 JWT，并再次从数据库读取有效用户、组织、角色和权限。因此即使 Token 尚未过期，禁用用户、停用组织或撤销角色也会即时生效。前端登录后调用 `GET /rbac/my-permissions`，仅用当前有效权限生成 Agent 模块导航。
5. `require_permission("权限编码")` 比对实时权限集合；无权限返回 403。

```mermaid
sequenceDiagram
    participant U as 管理端
    participant A as FastAPI 路由
    participant D as PostgreSQL
    U->>A: POST /auth/login
    A->>D: 校验组织、用户、密码摘要
    D-->>A: 用户及角色关系
    A->>D: 查询角色权限
    A-->>U: JWT access_token
    U->>A: 受保护接口 + Bearer Token
    A->>A: 解码 JWT
    A->>D: 实时解析用户/组织/角色/权限
    alt 有目标权限或 SUPER_ADMIN
        A-->>U: 执行业务操作
    else 无权限
        A-->>U: 403 缺少权限
    end
```

## 3. 组织隔离与数据权限

管理接口中的 `Principal` 包含 `org_id`、`role_codes`、`permission_keys` 与 `data_scope`。

- `RbacService` 的增删改查以 `principal.org_id` 作为数据边界。
- 角色、用户、部门、店铺、平台配置的 ID 在执行修改或授权时都会校验其归属组织；无法借用其他组织的 ID。
- `sys_user_shop` 表存储店铺级可见范围。业务模块查询店铺数据时应继续使用该表，而不能只信任前端传入的店铺 ID。
- 部门管理的“店铺分配”维护 `biz_department_shop` 的多对多关系：一个部门可管多店，一个店可被多个部门管理；变更部门归属不会自动给部门成员新增 `sys_user_shop` 授权。用户管理界面不展示店铺范围。
- `data_scope` 预留 `SELF`、`DEPT`、`DEPT_AND_CHILDREN`、`TENANT`、`ALL` 等粒度。当前 RBAC 管理端按组织过滤，但业务查询尚未统一按该字段实现五级数据过滤；界面上的选择不代表业务数据范围已经生效。

### Agent 模块导航与角色授权

项目权限表的“所属模块”定义了智能客服、驾驶舱设计、智能问数、销量预测、选品分析和补货预测等 Agent 分类。分类保存于 `sys_permission.module_name`，迁移脚本 `scripts/migrate_permission_modules.py` 根据项目权限表回填现有 29 项权限。`GET /rbac/my-permissions` 只返回当前用户已获授权的有效权限。管理端按模块分组展示权限目录与角色授权树；每个模块可整组勾选，子项仍按原 `perm_key` 写入 `sys_role_permission`。

左侧“Agent 模块”仅显示拥有至少一项权限的模块。没有 `system:tenant:roleManage` 的用户看不到平台配置、用户管理和组织管理入口；没有任何 Agent 权限时也不会看到 Agent 模块。导航显隐用于界面引导，后端接口仍以 `require_permission` 独立校验。当前 Agent 模块页展示授权范围和权限说明；实际 Agent 业务操作应由对应业务接口根据权限编码校验。

```mermaid
flowchart LR
    L[用户登录] --> M[实时解析角色与权限]
    M --> P[GET /rbac/my-permissions]
    P --> G[按所属 Agent 模块分组]
    G --> V{模块有已授权权限?}
    V -->|是| N[左侧展示模块及具体权限]
    V -->|否| H[隐藏模块入口]
    N --> A[访问业务接口时再次校验权限编码]
```

```mermaid
flowchart TD
    R[请求受保护接口] --> T[解析并校验 JWT]
    T --> U[查询有效用户与有效组织]
    U -->|无效| X401[401 未认证]
    U --> P[查询用户角色和权限]
    P --> S{SUPER_ADMIN?}
    S -->|是| B[按 org_id 执行业务查询]
    S -->|否| K{具备接口权限?}
    K -->|否| X403[403 无权限]
    K -->|是| B
    B --> D{需店铺范围?}
    D -->|是| US[追加 sys_user_shop 条件]
    D -->|否| O[返回当前组织数据]
    US --> O
```

## 4. 关键接口与权限要求

| 接口 | 用途 | 权限 |
| --- | --- | --- |
| `POST /auth/bootstrap` | 创建首个组织和管理员 | 匿名；仅系统无用户时 |
| `POST /auth/login` | 获取访问令牌 | 匿名 |
| `POST /auth/register` | 在已有组织注册待启用账号；不自动授予角色 | 匿名 |
| `GET /auth/me` | 获取当前身份和实时权限 | 已登录 |
| `/system/orgs` | 组织列表、新增、编辑 | `system:tenant:roleManage` |
| `/rbac/permissions` | 权限目录 | `system:tenant:roleManage` |
| `GET /rbac/my-permissions` | 本人的 Agent 权限及模块分类 | 已登录 |
| `/rbac/departments` | 部门管理 | `system:tenant:roleManage` |
| `PUT /rbac/departments/{id}/shops` | 替换部门店铺归属 | `system:tenant:roleManage` |
| `/rbac/roles` | 角色及角色授权 | `system:tenant:roleManage` |
| `/rbac/users` | 用户、角色管理及密码重置 | `system:tenant:roleManage` |
| `/rbac/shops` | 店铺管理 | `system:tenant:roleManage` |
| `/rbac/platform-configs` | 平台 API 连接配置 | `system:tenant:roleManage` |

自助注册时提交组织编码、用户名、真实姓名、密码及确认密码，邮箱和手机号可选。新用户默认 `DISABLED`、`SELF` 数据范围，且没有 `sys_user_role` 记录。组织管理员须在用户管理中启用账号并分配角色，用户才能登录并获得对应权限。重复用户名或邮箱返回 409，密码不一致返回 422。

## 5. 初始化测试环境

执行下列命令会幂等创建表、权限目录、`RBAC_TEST` 组织、角色、超级管理员及角色关联。脚本不会删除已有业务数据。

```powershell
$env:RBAC_DATABASE_URL = 'postgresql://postgres:123456@120.46.149.36:5432/ai_ecommerce'
python scripts/init_rbac_postgres.py --seed-test-org
```

测试登录账号：组织 `RBAC_TEST`，用户 `admin`，密码 `12345678`。密码仅在脚本执行时用于生成 Argon2id 摘要，数据库不会保存明文。

## 6. 类式路由规范

RBAC 路由继承 `BaseRouter`。每个模块在 `_register_routes()` 中用 `self.router.get/post/put/...(...)(self.handler)` 注册接口；路径、状态码、`summary`、`description` 和 Swagger 标签与处理函数在同一类中维护。新增接口时应：

1. 在 `_register_routes()` 添加注册语句及中文 Swagger 描述；
2. 在同一类添加处理函数和中文 docstring；
3. 对需要授权的接口加入 `Depends(MANAGE)` 或更细粒度的 `require_permission`；
4. 所有写接口在成功前调用 `_commit(db)`，由其负责异常回滚。
