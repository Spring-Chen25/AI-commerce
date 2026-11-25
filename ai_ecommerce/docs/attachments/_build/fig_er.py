# -*- coding: utf-8 -*-
"""图 7：概念 ER er-qa（本模块持有实体 + 外部只读实体）"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from svglib import SVG, C, export, write_mmd

W, H = 1620, 1170
s = SVG(W, H,
        title="图 er-qa　智能问数概念数据模型（只到实体与关系，不做物理表设计）",
        subtitle="实线框 = 本模块持有（配置侧可写 / 同步写入 / 运行侧写入）；虚线框 = 外部方提供、本模块只读。所有实体强制携带 org_id，跨组织访问拒绝并留痕（BR-QA-05）。")

EW = 300
COLX = [40, 412, 784, 1156]

BAND = [
    ("① 配置侧持有：指标与绑定", COLX[0], 60, "#f5faff", "#bae6fd"),
    ("② 配置侧持有：同步与留痕", COLX[1], 464, "#fbfdfb", "#d1fae5"),
    ("③ 运行侧持有：会话与证据", COLX[2], 868, "#fbfdff", "#dbeafe"),
    ("④ 外部只读：主数据与事实", COLX[3], 1272, "#fdfbff", "#ede9fe"),
]
for title, x, w, bg, bd in BAND:
    s.rect(x, 76, w, 950, fill=bg, stroke=bd, sw=1, rx=8)
    s.text(x + 14, 96, title, size=8.4, fill="#64748b", weight="bold")


def entity(x, y, title, code, attrs, owner="self", tone="blue"):
    pal = dict(blue=("#eff6ff", "#2563eb"), green=("#ecfdf5", "#10b981"),
               purple=("#f5f3ff", "#8b5cf6"), slate=("#f1f5f9", "#94a3b8"),
               amber=("#fffbeb", "#f59e0b"), teal=("#f0fdfa", "#0d9488"))
    bg, bd = pal[tone]
    h = 46 + len(attrs) * 15
    s.rect(x, y, EW, h, fill="#ffffff" if owner != "self" else bg, stroke=bd, sw=1.2, rx=7,
           dash=None if owner == "self" else "5 3")
    s.rect(x, y, EW, 26, fill=bg, stroke="none", rx=7)
    s.text(x + 12, y + 17, title, size=9.4, fill="#0f172a", weight="bold")
    s.text(x + EW - 12, y + 17, code, size=6.8, fill="#64748b", anchor="end",
           family="DejaVu Sans Mono, monospace")
    for i, (k, v) in enumerate(attrs):
        s.text(x + 12, y + 42 + i * 15, k, size=7.2, fill="#334155",
               family="DejaVu Sans Mono, monospace")
        s.text(x + 140, y + 42 + i * 15, v, size=7.0, fill="#64748b")
    return dict(x=x, y=y, w=EW, h=h)


# ---- ① 配置侧：指标与绑定 ----
metric = entity(COLX[0], 116, "指标定义", "BiMetric", [
    ("metric_code", "组织内唯一编码"),
    ("name / biz_definition", "名称与业务定义"),
    ("platform / dimensions", "适用平台与维度"),
    ("currency / display_rule", "币种与展示规则"),
    ("status", "DRAFT / PENDING / READY / DISABLED"),
], tone="teal")
mver = entity(COLX[0], 268, "指标口径版本", "BiMetricVersion", [
    ("version_id", "主键"),
    ("metric_code", "所属指标"),
    ("formula / notes", "公式与差异说明"),
    ("effective_from", "生效日期（不倒填）"),
    ("status", "草稿 / 已发布 / 已停用"),
    ("published_by / at", "发布人与时间"),
], tone="teal")
alias = entity(COLX[0], 430, "指标别名", "BiMetricAlias", [
    ("alias_id", "主键"),
    ("metric_code", "指向指标"),
    ("alias_text", "口语 / 平台叫法"),
    ("scope", "组织内唯一指向"),
], tone="teal")
bind = entity(COLX[0], 560, "指标数据绑定", "BiMetricBinding", [
    ("binding_id", "主键"),
    ("metric_code", "指标"),
    ("type", "REST / MCP / SIMULATION"),
    ("endpoint / params", "地址与参数（凭证掩码）"),
    ("schedule / retry", "频率与重试（TBD-QA-19）"),
    ("enabled", "同指标同平台仅一条"),
], tone="teal")
sim = entity(COLX[0], 800, "模拟应用配置", "BiSimulationApp", [
    ("app_id", "主键"),
    ("binding_id", "对应模拟绑定"),
    ("fixture_ref", "样例数据引用"),
    ("is_cleared / cleared_at", "是否已清除"),
], tone="teal")

# ---- ② 配置侧：同步与留痕 ----
sync = entity(COLX[1], 116, "同步记录", "BiSyncRecord", [
    ("sync_id", "主键"),
    ("binding_id", "关联绑定"),
    ("trigger", "MANUAL / SCHEDULED"),
    ("started_at / ended_at", "起止时间"),
    ("result", "SUCCESS / PARTIAL / FAILED"),
    ("error_class / ref_no", "错误分类与参考号"),
    ("rows_written", "写入行数（失败为 0）"),
], tone="green")
cfglog = entity(COLX[1], 480, "配置变更留痕", "BiConfigChangeLog", [
    ("change_id", "主键"),
    ("object_type / id", "指标/版本/别名/绑定/模拟"),
    ("action", "CREATE / UPDATE / PUBLISH …"),
    ("before / after", "旧值 → 新值"),
    ("operator / at", "操作人与时间"),
], tone="green")
snap = entity(COLX[1], 300, "指标快照", "BiMetricSnapshot", [
    ("snapshot_id", "主键"),
    ("metric_code / version", "指标与口径版本"),
    ("shop_id / platform", "店铺与平台"),
    ("snapshot_date", "业务日期"),
    ("value / currency", "数值与币种"),
    ("quality_flag", "COMPLETE / PARTIAL / …"),
    ("source_type", "REST / MCP / SIMULATION / 规则"),
], tone="green")

# ---- ③ 运行侧：会话与证据 ----
conv = entity(COLX[2], 116, "问数会话", "BiConversation", [
    ("session_id", "前端生成 UUID"),
    ("org_id / user_id", "租户 / 发起人"),
    ("created_at / last_active_at", "时间戳"),
    ("status", "ACTIVE / CLOSED"),
], tone="blue")
turn = entity(COLX[2], 250, "问数轮次", "BiConversationTurn", [
    ("turn_id", "主键"),
    ("question", "原始问题（脱敏存档）"),
    ("slots / intent", "槽位 / 意图"),
    ("turn_status / quality_status", "终态（见 §7.5）"),
    ("metric_version", "本轮口径版本"),
    ("data_as_of", "数据截止时间"),
    ("elapsed_ms / is_memorized", "耗时与是否入记忆"),
], tone="blue")
ev = entity(COLX[2], 700, "证据摘要", "EvidenceRecord", [
    ("evidence_id", "主键"),
    ("turn_id", "关联轮次"),
    ("metric_code / version", "口径与版本"),
    ("source_ref", "来源标识（脱敏）"),
    ("data_as_of", "数据截止"),
    ("row_refs", "明细行引用（快照主键）"),
], tone="blue")
audit = entity(COLX[2], 555, "查询审计", "QueryAuditLog", [
    ("audit_id", "主键"),
    ("org_id / user_id", "主体"),
    ("question_digest", "问题摘要"),
    ("result_status", "终态"),
    ("ref_no", "错误或请求参考号"),
], tone="amber")
fb = entity(COLX[2], 425, "回答反馈", "AnswerFeedback", [
    ("feedback_id", "主键"), ("turn_id", "关联轮次"),
    ("rating", "准确 / 有问题"), ("note", "补充说明"),
], tone="amber")

# ---- ④ 外部只读 ----
shop = entity(COLX[3], 116, "店铺", "biz_shop", [
    ("shop_id", "主键"), ("org_id", "租户"),
    ("platform / site", "平台与站点"), ("status", "授权状态"),
], owner="up", tone="slate")
org = entity(COLX[3], 268, "组织（租户）", "sys_org", [
    ("org_id", "主键，隔离边界"),
    ("org_code", "登录组织编码"), ("status", "启停用"),
], owner="up", tone="slate")
user = entity(COLX[3], 400, "用户", "sys_user", [
    ("user_id", "主键"), ("org_id", "租户"), ("role_codes", "角色集合"),
], owner="up", tone="slate")
inv = entity(COLX[3], 520, "库存事实", "InventoryPosition", [
    ("position_id", "主键"), ("sku / shop_id", "商品与店铺"),
    ("available / reserved", "可售 / 预留"),
    ("safety_stock", "安全库存（配置侧读取）"),
    ("snapshot_at", "快照时间"),
], owner="up", tone="slate")
doc = entity(COLX[3], 690, "训练资料", "KnowledgeDocument", [
    ("doc_id", "主键"), ("domain", "数据域"),
    ("status", "INDEXING / READY / FAILED"),
    ("sha256", "内容哈希"),
], owner="up", tone="purple")
conn = entity(COLX[3], 840, "平台连接授权", "DataPlatformConn", [
    ("conn_id", "主键"), ("platform", "平台"),
    ("auth_status", "授权状态"), ("expires_at", "到期时间"),
], owner="up", tone="slate")


def arrow(pts, label="", color="#94a3b8", dash=None, label_at=None):
    d = "M" + " L".join(f"{x:.0f},{y:.0f}" for x, y in pts)
    s.path(d, stroke=color, sw=1.15, dash=dash)
    if label:
        lx, ly = label_at if label_at else (pts[0][0] + 6, pts[0][1] - 5)
        s.text(lx, ly, label, size=7.0, fill=color)


# 指标 → 版本 → 快照（同列右侧通道）
CH = COLX[0] + EW - 108
arrow([(CH, metric["y"] + metric["h"]), (CH, mver["y"] - 2)], "1..N", "#0d9488")
arrow([(CH, mver["y"] + mver["h"]), (CH, alias["y"] - 2)], "1..N 别名", "#0d9488")
arrow([(COLX[0] + EW - 60, alias["y"] + alias["h"]), (COLX[0] + EW - 60, bind["y"] - 2)], "1..N 绑定", "#0d9488")

# 绑定 → 同步记录（跨列）
G1 = 376
arrow([(COLX[0] + EW, bind["y"] + 30), (G1, bind["y"] + 30), (G1, sync["y"] + 60), (COLX[1] - 2, sync["y"] + 60)],
      "1..N", "#10b981", label_at=(G1 + 6, bind["y"] + 24))
# 绑定 → 模拟应用
arrow([(COLX[0] + EW, bind["y"] + 92), (COLX[0] + EW + 22, bind["y"] + 92), (COLX[0] + EW + 22, sim["y"] + 22), (COLX[0] + EW - 2, sim["y"] + 22)],
      "0..1", "#0d9488", label_at=(COLX[0] + EW + 26, sim["y"] + 16))

# 同步 → 指标快照（同列，左侧通道）
SXL = COLX[1] + 46
arrow([(SXL, sync["y"] + sync["h"]), (SXL, snap["y"] - 2)], "写入指标点", "#10b981", label_at=(SXL + 6, sync["y"] + sync["h"] + 12))
# 配置变更留痕：由「目录实体（指标定义）」覆盖全部配置对象，走②列右侧通道向下
s.text(COLX[1] + 12, cfglog["y"] + cfglog["h"] + 16,
       "记录对象 = 指标定义 / 口径版本 / 别名 / 绑定 / 模拟应用", size=7.0, fill="#059669")

# 运行侧：会话 → 轮次 → 反馈 → 审计 → 证据
CX = COLX[2] + 60
arrow([(CX, conv["y"] + conv["h"]), (CX, turn["y"] - 2)], "1..N", "#2563eb")
arrow([(CX, turn["y"] + turn["h"]), (CX, fb["y"] - 2)], "0..1 反馈", "#f59e0b", label_at=(CX + 6, turn["y"] + turn["h"] + 14))
ax = COLX[2] + EW + 16
arrow([(COLX[2] + EW, turn["y"] + 60), (ax, turn["y"] + 60), (ax, audit["y"] + 15), (COLX[2] + EW + 2, audit["y"] + 15)],
      "每轮一行摘要", "#f59e0b", dash="4 3", label_at=(ax + 4, turn["y"] + 54))
arrow([(CX, audit["y"] + audit["h"]), (CX, ev["y"] - 2)], "1..N 证据", "#2563eb", label_at=(CX + 6, audit["y"] + audit["h"] + 14))

# 证据 → 指标快照（跨列虚线：引用而非外键）
G2 = COLX[1] + EW + 10
arrow([(COLX[2], ev["y"] + 30), (G2, ev["y"] + 30), (G2, snap["y"] + 100), (COLX[1] + EW - 2, snap["y"] + 100)],
      "row_refs → 快照主键（引用，非外键）", "#2563eb", dash="5 3", label_at=(G2 + 6, snap["y"] + 94))
# 轮次 → 口径版本（跨两列，走底部通道）
LX = COLX[1] + EW + 52      # ②③ 之间的竖向通道
arrow([(COLX[2], turn["y"] + 46), (LX, turn["y"] + 46), (LX, 980), (COLX[0] + 30, 980), (COLX[0] + 30, mver["y"] + mver["h"] + 4)],
      "引用口径版本（N:1）", "#2563eb", dash="5 3", label_at=(COLX[0] + 50, 974))

# 外部只读的引用关系（文字化，不画长线）
s.rect(COLX[3] + 14, 1046, EW - 28, 74, fill="#ffffff", stroke="#cbd5e1", sw=1, rx=6, dash="4 3")
s.text(COLX[3] + 28, 1064, "跨实体约束（文字表述，避免长线交叉）", size=7.8, fill="#334155", weight="bold")
s.text(COLX[3] + 28, 1082, "org → 全部实体：1..N，强制隔离作用域", size=7.2, fill="#64748b")
s.text(COLX[3] + 28, 1096, "shop → 快照 / 库存：1..N，按店铺取数", size=7.2, fill="#64748b")
s.text(COLX[3] + 28, 1110, "conn → 绑定：绑定只引用已授权连接标识", size=7.2, fill="#64748b")

# 读法说明
s.rect(40, 1020, 700, 56, fill="#ffffff", stroke="#e2e8f0", sw=1, rx=6)
s.text(56, 1038, "读法：卡片上方为实体名与编码；左侧为关键属性，右侧为语义说明。实线框 = 本模块持有，虚线框 = 外部只读。", size=8.0, fill="#475569")
s.text(56, 1056, "关系基数：1 : 1..N（或 0..1）；虚线表示“引用 / 只读”，不代表外键级联。", size=8.0, fill="#475569")

s.rect(40, 1090, 700, 58, fill="#f8fbff", stroke="#bfdbfe", sw=1, rx=6)
s.text(56, 1110, "保留与脱敏：轮次单会话最多 50 轮、30 天清理（TBD-QA-09）；审计保留 TBD-QA-15；同步记录保留 TBD-QA-19；", size=8.0, fill="#334155")
s.text(56, 1130, "已发布口径永久保留（含停用版本），历史答案按生效日期分段复现。", size=8.0, fill="#334155")

out = os.path.join(os.path.dirname(__file__), "..", "er-qa.svg")
s.save(out)
print(export(out, dpi=160))

write_mmd(os.path.join(os.path.dirname(__file__), "..", "er-qa.mmd"), """
%% 图 er-qa 智能问数概念 ER（Mermaid 源码；成图见 er-qa.svg / .png）
erDiagram
    BI_METRIC ||--o{ BI_METRIC_VERSION : "口径版本 1..N"
    BI_METRIC ||--o{ BI_METRIC_ALIAS : "别名 1..N"
    BI_METRIC ||--o{ BI_METRIC_BINDING : "绑定 1..N（同平台启用≤1）"
    BI_METRIC_VERSION ||--o{ BI_METRIC_SNAPSHOT : "口径落地 1..N"
    BI_METRIC_BINDING ||--o{ BI_SYNC_RECORD : "同步记录 1..N"
    BI_METRIC_BINDING ||--o| BI_SIMULATION_APP : "模拟应用 0..1"
    BI_SYNC_RECORD ||--o{ BI_METRIC_SNAPSHOT : "同步写入"
    BI_CONFIG_CHANGE_LOG }o--|| BI_METRIC : "配置变更留痕"

    BI_CONVERSATION ||--o{ BI_CONVERSATION_TURN : "包含 1..N"
    BI_CONVERSATION_TURN ||--o{ EVIDENCE_RECORD : "证据 1..N"
    BI_CONVERSATION_TURN ||--o| ANSWER_FEEDBACK : "反馈 0..1"
    BI_CONVERSATION_TURN ||--o{ QUERY_AUDIT_LOG : "每轮一行摘要"
    BI_CONVERSATION_TURN }o--|| BI_METRIC_VERSION : "引用口径版本"
    EVIDENCE_RECORD }o--|| BI_METRIC_SNAPSHOT : "row_refs 指向快照主键"

    BIZ_SHOP ||--o{ BI_METRIC_SNAPSHOT : "按店铺取数"
    BIZ_SHOP ||--o{ INVENTORY_POSITION : "库存快照"
    SYS_ORG ||--o{ BI_METRIC : "org_id 隔离作用域"
    SYS_ORG ||--o{ BI_CONVERSATION : "org_id 隔离作用域"
    SYS_USER ||--o{ BI_CONVERSATION : "发起人"
    DATA_PLATFORM_CONN ||--o{ BI_METRIC_BINDING : "绑定引用已授权连接"
    KNOWLEDGE_DOCUMENT ||--o{ SQL_VALIDATION_RECORD : "被引用 0..N"

    BI_METRIC { string metric_code PK  string name  string status }
    BI_METRIC_VERSION { string version_id PK  string formula  date effective_from  string status }
    BI_METRIC_BINDING { string binding_id PK  string type  string enabled }
    BI_SYNC_RECORD { string sync_id PK  string result  string error_class }
    BI_METRIC_SNAPSHOT { string snapshot_id PK  date snapshot_date  string source_type }
    BI_CONVERSATION { string session_id PK  string org_id  string user_id }
""")
