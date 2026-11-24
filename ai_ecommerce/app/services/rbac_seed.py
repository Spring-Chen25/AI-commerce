"""项目提供的角色、权限及角色权限关联的种子目录。"""

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.rbac import Permission, Role, RolePermission


PERMISSIONS = [
    ("cs:goods:import", "下载导入推荐商品", "智能客服 Agent"),
    ("cs:goods:rebuildIndex", "重建向量商品索引", "智能客服 Agent"),
    ("cs:mock:sendMsg", "模拟买家发送消息", "智能客服 Agent"),
    ("cs:session:view", "查看会话与意图", "智能客服 Agent"),
    ("cs:session:takeover", "人工接管会话", "智能客服 Agent"),
    ("cs:session:translateReview", "翻译复核回复", "智能客服 Agent"),
    ("cs:ticket:create", "创建售后工单", "智能客服 Agent"),
    ("cs:ticket:view", "查看售后工单", "智能客服 Agent"),
    ("cs:ticket:audit", "售后工单审批", "智能客服 Agent"),
    ("bi:dashboard:design", "编排 BI 驾驶舱", "驾驶舱设计 Agent"),
    ("bi:dashboard:saveDraft", "保存驾驶舱草稿", "驾驶舱设计 Agent"),
    ("bi:dashboard:publish", "发布驾驶舱", "驾驶舱设计 Agent"),
    ("bi:dashboard:view", "查看已发布驾驶舱", "驾驶舱设计 Agent"),
    ("bi:query:ask", "自然语言问数查询", "智能问数 Agent"),
    ("bi:metric:edit", "维护指标口径与知识库", "智能问数 Agent"),
    ("forecast:sales:run", "执行 SKU 销量预测", "销量预测 Agent"),
    ("forecast:sales:editActual", "采集 & 人工修正实际销量", "销量预测 Agent"),
    ("forecast:model:manage", "模型注册启停管理", "销量预测 Agent"),
    ("product:source:upload", "登记 & 导入选品数据源", "选品分析 Agent"),
    ("product:research:view", "查看选品研究档案", "选品分析 Agent"),
    ("product:research:audit", "选品测款人工决策", "选品分析 Agent"),
    ("replenish:plan:submit", "补货方案测算 & 提交计划", "补货预测 Agent"),
    ("replenish:cost:edit", "维护成本卡凭证", "补货预测 Agent"),
    ("replenish:plan:audit", "补货计划审批", "补货预测 Agent"),
    ("replenish:purchase:create", "创建内部采购任务", "补货预测 Agent"),
    ("replenish:receive:save", "登记收货质检凭证", "补货预测 Agent"),
    ("replenish:deliver:save", "登记发货运单", "补货预测 Agent"),
    ("replenish:audit:view", "复盘审计查看", "补货预测 Agent"),
    ("system:org:roleManage", "角色租户管理", "系统管理"),
]
PERMISSION_MODULES = {key: module for key, _, module in PERMISSIONS}

ROLES = [
    ("GOODS_OPER", "商品运营"), ("MOCK_BUYER", "模拟买家（仅演示环境）"),
    ("CS_STAFF", "客服人员"), ("CS_SPECIALIST", "售后专员"), ("CS_SUPERVISOR", "售后主管"),
    ("BI_DESIGNER", "BI 设计者"), ("BI_VIEWER", "BI 浏览者"), ("OP_ANALYST", "运营分析人员"),
    ("METRIC_ADMIN", "指标 / 知识管理员"), ("ALG_ADMIN", "算法负责人"), ("DATA_OPER", "数据运营人员"),
    ("SELECT_AUDITOR", "研究与审批人员"), ("PLANNER", "运营 / 计划员"), ("COST_VERIFY", "成本核验人"),
    ("REPLENISH_AUDITOR", "补货审批人"), ("PURCHASER", "采购员"), ("WH_INSPECT", "仓库质检"),
    ("LOGISTICS", "物流专员"), ("AUDIT_ANALYST", "分析 / 复盘人员"), ("SUPER_ADMIN", "超级管理员"),
]

ROLE_PERMISSION_KEYS = {
    "GOODS_OPER": ["cs:goods:import", "cs:goods:rebuildIndex"],
    "MOCK_BUYER": ["cs:mock:sendMsg"],
    "CS_STAFF": ["cs:session:view", "cs:session:takeover", "cs:session:translateReview", "cs:ticket:create", "cs:ticket:view"],
    "CS_SPECIALIST": ["cs:ticket:create", "cs:ticket:view"],
    "CS_SUPERVISOR": ["cs:ticket:view", "cs:ticket:audit"],
    "BI_DESIGNER": ["bi:dashboard:design", "bi:dashboard:saveDraft", "bi:dashboard:publish", "bi:dashboard:view"],
    "BI_VIEWER": ["bi:dashboard:view"],
    "OP_ANALYST": ["bi:query:ask", "forecast:sales:run", "forecast:sales:editActual"],
    "METRIC_ADMIN": ["bi:metric:edit"], "ALG_ADMIN": ["forecast:model:manage"],
    "DATA_OPER": ["product:source:upload", "product:research:view"],
    "SELECT_AUDITOR": ["product:research:view", "product:research:audit"],
    "PLANNER": ["replenish:plan:submit"], "COST_VERIFY": ["replenish:cost:edit"],
    "REPLENISH_AUDITOR": ["replenish:plan:audit"], "PURCHASER": ["replenish:purchase:create"],
    "WH_INSPECT": ["replenish:receive:save"], "LOGISTICS": ["replenish:deliver:save"],
    "AUDIT_ANALYST": ["replenish:audit:view"], "SUPER_ADMIN": ["system:org:roleManage"],
}


def ensure_permission_catalog(db: Session) -> dict[str, Permission]:
    """幂等写入项目权限目录，返回按权限编码索引的实体。"""
    existing = {p.perm_key: p for p in db.scalars(select(Permission)).all()}
    for key, name, module in PERMISSIONS:
        if key not in existing:
            item = Permission(perm_key=key, perm_name=name, module_name=module, perm_type="API", status="ENABLED")
            db.add(item)
            existing[key] = item
        else:
            existing[key].module_name = module
    db.flush()
    return existing


def seed_org_roles(db: Session, org_id: int, actor_id: int | None = None) -> None:
    """为新租户创建完整角色集及其最小权限关联，重复调用安全。"""
    permissions = ensure_permission_catalog(db)
    current = {
        role.role_code: role
        for role in db.scalars(select(Role).where(Role.org_id == org_id)).all()
    }
    for sort, (code, name) in enumerate(ROLES, start=1):
        role = current.get(code)
        if role is None:
            role = Role(
                org_id=org_id, role_code=code, role_name=name, sort=sort,
                data_scope="ALL" if code == "SUPER_ADMIN" else "SELF", created_by=actor_id,
            )
            db.add(role)
            db.flush()
        assigned = set(db.scalars(select(RolePermission.perm_id).where(RolePermission.role_id == role.id)).all())
        target = ROLE_PERMISSION_KEYS[code]
        for key in target:
            permission = permissions[key]
            if permission.id not in assigned:
                db.add(RolePermission(role_id=role.id, perm_id=permission.id, created_by=actor_id))
