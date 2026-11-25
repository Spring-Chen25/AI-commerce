# -*- coding: utf-8 -*-
"""图 6：概念 ER 图 er-qa（分域四列，跨列关系走顶部通道）"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from svglib import SVG, C, export, write_mmd

W, H = 1620, 1010
s = SVG(W, H,
        title="图 er-qa　智能问数概念数据模型（只到实体与关系，不做物理表设计）",
        subtitle="实线 = 本模块写入或持有的实体；虚线 = 上游指标域 / 库存域提供、本模块只读。所有实体强制携带 org_id，跨组织访问拒绝并留痕（BR-QA-05）。")

EW = 330
COLX = [40, 452, 864, 1276]

BAND = [
    ("① 本模块写入：会话、轮次、反馈、审计", COLX[0], 60, "#fcfdff", "#dbeafe"),
    ("② 本模块写入：证据与 SQL 校验", COLX[1], 452, "#fbfdff", "#e0f2fe"),
    ("③ 上游只读：指标与库存事实", COLX[2], 864, "#fbfdfb", "#d1fae5"),
    ("④ 上游只读：治理与主数据", COLX[3], 1276, "#fdfbff", "#ede9fe"),
]
for title, x, w, bg, bd in BAND:
    s.rect(x, 76, 330, 856, fill=bg, stroke=bd, sw=1, rx=8)
    s.text(x + 14, 96, title, size=8.4, fill="#64748b", weight="bold")


def entity(x, y, title, code, attrs, owner="self", tone="blue"):
    pal = dict(blue=("#eff6ff", "#2563eb"), green=("#ecfdf5", "#10b981"),
               purple=("#f5f3ff", "#8b5cf6"), slate=("#f1f5f9", "#94a3b8"),
               amber=("#fffbeb", "#f59e0b"))
    bg, bd = pal[tone]
    h = 46 + len(attrs) * 15
    s.rect(x, y, EW, h, fill="#ffffff" if owner != "self" else bg, stroke=bd, sw=1.2, rx=7,
           dash=None if owner == "self" else "5 3")
    s.rect(x, y, EW, 26, fill=bg, stroke="none", rx=7)
    s.text(x + 12, y + 17, title, size=9.6, fill="#0f172a", weight="bold")
    s.text(x + EW - 12, y + 17, code, size=7.2, fill="#64748b", anchor="end",
           family="DejaVu Sans Mono, monospace")
    for i, (k, v) in enumerate(attrs):
        s.text(x + 12, y + 42 + i * 15, k, size=7.4, fill="#334155",
               family="DejaVu Sans Mono, monospace")
        s.text(x + 150, y + 42 + i * 15, v, size=7.2, fill="#64748b")
    return dict(x=x, y=y, w=EW, h=h)


# ① 本模块写入
conv = entity(COLX[0], 116, "问数会话", "BiConversation",
              [("session_id", "前端生成 UUID"),
               ("org_id / user_id", "租户 / 发起人"),
               ("created_at", "创建时间（仅存时间，不存内容）"),
               ("last_active_at", "最后活跃"),
               ("status", "ACTIVE / CLOSED")])
turn = entity(COLX[0], 288, "问数轮次", "BiConversationTurn",
              [("turn_id", "主键"),
               ("question", "原始问题（脱敏后存档）"),
               ("slots / intent", "槽位 / 意图（查询·追问·写入）"),
               ("turn_status", "终态，见 §7.5"),
               ("quality_status", "COMPLETE / PARTIAL / …"),
               ("metric_version", "本轮所用口径版本"),
               ("data_as_of", "数据截止时间"),
               ("tool_trace", "工具与耗时"),
               ("elapsed_ms", "端到端耗时"),
               ("is_memorized", "是否进入上下文")])
fb = entity(COLX[0], 522, "回答反馈", "AnswerFeedback",
            [("feedback_id", "主键"), ("turn_id", "关联轮次"),
             ("rating", "准确 / 有问题"), ("note", "补充说明（可选）")], tone="green")
audit = entity(COLX[0], 648, "查询审计", "QueryAuditLog",
               [("audit_id", "主键"), ("org_id / user_id", "主体"),
                ("question_digest", "问题摘要"), ("result_status", "终态"),
                ("ref_no", "错误或请求参考号")], tone="amber")

# ② 本模块写入
ev = entity(COLX[1], 116, "证据摘要", "EvidenceRecord",
            [("evidence_id", "主键"),
             ("turn_id", "关联轮次"),
             ("metric_code / version", "口径与版本"),
             ("source_ref", "来源标识（脱敏）"),
             ("data_as_of", "数据截止"),
             ("row_refs", "明细行引用（快照主键）")], tone="green")
sqlrec = entity(COLX[1], 320, "SQL 校验记录", "SqlValidationRecord",
                [("record_id", "主键"), ("turn_id", "关联轮次"),
                 ("doc_refs", "引用的 READY 训练资料"),
                 ("sql_digest", "单条 SELECT 摘要"),
                 ("verdict", "通过 / 拒绝（命中规则）"),
                 ("row_count / elapsed", "行数与耗时")], tone="purple")

# ③ 上游只读
metric = entity(COLX[2], 116, "指标定义", "MetricDefinition",
                [("metric_code", "唯一编码"),
                 ("name / aliases", "名称与口语别称"),
                 ("platform", "适用平台"),
                 ("dimensions", "可用维度")], owner="up", tone="green")
mver = entity(COLX[2], 264, "指标口径版本", "MetricVersion",
              [("version_id", "主键"), ("metric_code", "所属指标"),
               ("formula", "计算公式"), ("effective_from", "生效日期"),
               ("status", "草稿 / 已发布 / 停用")], owner="up", tone="green")
snap = entity(COLX[2], 438, "指标快照", "MetricSnapshot",
              [("snapshot_id", "主键"), ("shop_id / platform", "店铺与平台"),
               ("metric_code / version", "指标与口径版本"),
               ("snapshot_date", "业务日期"),
               ("value / currency", "数值与币种"),
               ("quality_flag", "COMPLETE / PARTIAL / …"),
               ("source_type", "SIMULATION / REST / MCP / 规则计算")],
              owner="up", tone="green")
inv = entity(COLX[2], 702, "库存事实", "InventoryPosition",
             [("position_id", "主键"), ("sku / shop_id", "商品与店铺"),
              ("available / reserved", "可售 / 预留"),
              ("safety_stock", "安全库存"), ("location", "库位"),
              ("snapshot_at", "快照时间")], owner="up", tone="green")

# ④ 上游只读
doc = entity(COLX[3], 116, "训练资料", "KnowledgeDocument",
             [("doc_id", "主键"), ("domain", "数据域"),
              ("status", "INDEXING / READY / FAILED"),
              ("sha256", "内容哈希"), ("owner_id", "维护人")], owner="up", tone="purple")
binding = entity(COLX[3], 300, "指标数据绑定", "MetricBinding",
                 [("binding_id", "主键"), ("metric_code", "指标"),
                  ("type", "REST / MCP / SIMULATION"),
                  ("schedule", "同步频率"),
                  ("last_status", "SUCCESS / DELAYED / FAILED")], owner="up", tone="slate")
shop = entity(COLX[3], 466, "店铺", "biz_shop",
              [("shop_id", "主键"), ("org_id", "租户"), ("platform", "AMAZON / SHOPEE / TTS"),
               ("site", "站点"), ("status", "授权状态")], owner="up", tone="slate")
org = entity(COLX[3], 626, "组织（租户）", "sys_org",
             [("org_id", "主键，隔离边界"), ("org_code", "登录组织编码"),
              ("status", "启停用")], owner="up", tone="slate")
user = entity(COLX[3], 756, "用户（发起人）", "sys_user",
              [("user_id", "主键"), ("org_id", "租户"), ("role_codes", "角色集合")],
              owner="up", tone="slate")

# ---------- 关系 ----------
XX = COLX[2] + EW - 120      # ⑶列内右侧垂直通道
GUT = (COLX[1] + EW + COLX[2]) / 2   # ②→③ 列间通道


def arrow(pts, label="", c1="", c2="", color="#94a3b8", dash=None):
    d = "M" + " L".join(f"{x:.0f},{y:.0f}" for x, y in pts)
    s.path(d, stroke=color, sw=1.15, dash=dash)
    if c1:
        s.text(pts[0][0] + 4, pts[0][1] - 5, c1, size=7.2, fill=color)
    if c2:
        s.text(pts[-1][0] - 20, pts[-1][1] + 12, c2, size=7.2, fill=color)
    if label:
        mx = sum(p[0] for p in pts) / len(pts)
        my = sum(p[1] for p in pts) / len(pts)
        s.text(mx, my - 5, label, size=7.2, fill="#94a3b8", anchor="middle")


# 会话 → 轮次（同列垂直）
arrow([(COLX[0] + 60, conv["y"] + conv["h"]), (COLX[0] + 60, turn["y"] - 2)], "1..N", "1", "N", "#2563eb")
# 轮次 → 反馈
arrow([(COLX[0] + 60, turn["y"] + turn["h"]), (COLX[0] + 60, fb["y"] - 2)], "0..1", "", "", "#10b981")
# 反馈 → 审计（同列）
arrow([(COLX[0] + 60, fb["y"] + fb["h"]), (COLX[0] + 60, audit["y"] - 2)], "", "", "", "#f59e0b", dash="4 3")

# 轮次 → 证据（跨 1 个 gutter）
arrow([(COLX[0] + EW, turn["y"] + 30), (COLX[1] - 2, turn["y"] + 30)], "1..N", "1", "N", "#10b981")
# 轮次 → SQL 校验（跨 gutter，虚线）
arrow([(COLX[0] + EW, turn["y"] + 90), (COLX[1] - 2, turn["y"] + 90)], "0..N（P2）", "", "", "#8b5cf6", dash="5 3")
# 轮次 → 审计（短虚线指向下方）
arrow([(COLX[0] + EW - 40, turn["y"] + turn["h"]), (COLX[0] + EW - 40, audit["y"] + 20)], "每轮一行摘要", "", "", "#f59e0b", dash="4 3")

# 证据 → 指标快照（跨 gutter 走外侧通道，避免穿过③列卡片）
arrow([(COLX[1] + EW, ev["y"] + 40), (GUT, ev["y"] + 40), (GUT, snap["y"] + 30), (COLX[2] - 2, snap["y"] + 30)],
      "", "1..N", "1", "#10b981", dash="5 3")
s.text(GUT + 8, snap["y"] + 22, "row_refs → 快照主键", size=7.2, fill="#10b981")
arrow([(COLX[1] + EW, ev["y"] + 74), (GUT + 16, ev["y"] + 74), (GUT + 16, mver["y"] + 40), (COLX[2] - 2, mver["y"] + 40)],
      "", "N", "1", "#10b981", dash="4 3")
s.text(GUT + 24, mver["y"] + 32, "口径版本", size=7.2, fill="#10b981")

# 指标定义 → 版本（⑶列内右侧垂直，避开通道线）
arrow([(XX, metric["y"] + metric["h"]), (XX, mver["y"] - 2)], "1..N", "1", "N", "#10b981")
arrow([(XX, mver["y"] + mver["h"]), (XX, snap["y"] - 2)], "1..N", "1", "N", "#10b981")

# SQL 校验与训练资料：以注释表达（训练资料位于④列，不跨两列画长线）
s.rect(COLX[1] + 16, sqlrec["y"] + sqlrec["h"] + 14, EW - 32, 44, fill="#ffffff",
       stroke="#c4b5fd", sw=1, rx=6, dash="4 3")
s.text(COLX[1] + 28, sqlrec["y"] + sqlrec["h"] + 32, "doc_refs → ④列「训练资料」中的 READY 文档", size=7.4, fill="#5b21b6")
s.text(COLX[1] + 28, sqlrec["y"] + sqlrec["h"] + 48, "仅允许引用本组织已就绪资料，索引中/失败不可用", size=7.4, fill="#5b21b6")

# 全局约束说明（不画跨列长线，避免视觉噪声）
s.rect(COLX[3] + 12, 862, EW - 24, 58, fill="#ffffff", stroke="#cbd5e1", sw=1, rx=6, dash="4 3")
s.text(COLX[3] + 24, 880, "跨列关系（以文字表述，避免长线交叉）", size=8.0, fill="#334155", weight="bold")
s.text(COLX[3] + 24, 898, "org → 全部实体：1..N，强制隔离作用域", size=7.2, fill="#64748b")
s.text(COLX[3] + 24, 912, "shop → 快照 / 库存：1..N，按店铺取数", size=7.2, fill="#64748b")

# 读法说明
s.rect(40, 950, 760, 48, fill="#ffffff", stroke="#e2e8f0", sw=1, rx=6)
s.text(56, 970, "读法：方框内上部为实体，左侧为属性，右侧为语义说明；卡片右上角为实体编码。", size=8.2, fill="#475569")
s.text(56, 988, "关系符号：1 — 1..N（或 0..1）；虚线表示“引用 / 只读”，不代表外键级联。", size=8.2, fill="#475569")

s.rect(824, 950, 756, 48, fill="#f8fbff", stroke="#bfdbfe", sw=1, rx=6)
s.text(840, 970, "保留与脱敏（概念级）：轮次单会话最多 50 轮、30 天前清理（TBD-QA-09）；审计保留期见 TBD-QA-15；", size=8.2, fill="#334155")
s.text(840, 988, "审计只存问题摘要与结果状态，不复制明细数值；快照重算后被替代的历史证据仅标注、不覆盖。", size=8.2, fill="#334155")

out = os.path.join(os.path.dirname(__file__), "..", "er-qa.svg")
s.save(out)
print(export(out, dpi=160))

write_mmd(os.path.join(os.path.dirname(__file__), "..", "er-qa.mmd"), """
%% 图 er-qa 智能问数概念 ER（Mermaid 源码；成图见 er-qa.svg / .png）
erDiagram
    BI_CONVERSATION ||--o{ BI_CONVERSATION_TURN : "包含 1..N"
    BI_CONVERSATION_TURN ||--o| ANSWER_FEEDBACK : "可评价 0..1"
    BI_CONVERSATION_TURN ||--o{ EVIDENCE_RECORD : "证据摘要 1..N"
    BI_CONVERSATION_TURN ||--o{ SQL_VALIDATION_RECORD : "P2 校验 0..N"
    BI_CONVERSATION_TURN }o--|| METRIC_VERSION : "引用口径版本"
    EVIDENCE_RECORD }o--|| METRIC_SNAPSHOT : "row_refs 指向快照主键"
    METRIC_DEFINITION ||--o{ METRIC_VERSION : "版本 1..N"
    METRIC_VERSION ||--o{ METRIC_SNAPSHOT : "口径落地 1..N"
    BIZ_SHOP ||--o{ METRIC_SNAPSHOT : "按店铺取数"
    BIZ_SHOP ||--o{ INVENTORY_POSITION : "库存快照"
    KNOWLEDGE_DOCUMENT ||--o{ SQL_VALIDATION_RECORD : "被引用 0..N"
    METRIC_BINDING }o--|| METRIC_DEFINITION : "上游绑定（只读）"
    SYS_ORG ||--o{ BI_CONVERSATION : "org_id 隔离作用域"
    SYS_USER ||--o{ BI_CONVERSATION : "发起人"
    SYS_ORG ||--o{ BIZ_SHOP : "拥有"
    SYS_ORG ||--o{ SYS_USER : "拥有"
    BI_CONVERSATION_TURN ||--o{ QUERY_AUDIT_LOG : "每轮一行摘要"

    BI_CONVERSATION { string session_id PK  string org_id  string user_id  string status }
    BI_CONVERSATION_TURN { string turn_id PK  string question  string turn_status  string quality_status  string metric_version  datetime data_as_of  bool is_memorized }
    ANSWER_FEEDBACK { string feedback_id PK  string rating }
    EVIDENCE_RECORD { string evidence_id PK  string metric_version  string source_ref  datetime data_as_of }
    SQL_VALIDATION_RECORD { string record_id PK  string verdict  int row_count }
    QUERY_AUDIT_LOG { string audit_id PK  string question_digest  string result_status  string ref_no }
    METRIC_DEFINITION { string metric_code PK  string aliases  string platform }
    METRIC_VERSION { string version_id PK  string formula  date effective_from  string status }
    METRIC_SNAPSHOT { string snapshot_id PK  string shop_id  string metric_code  string version  string currency  string quality_flag }
    INVENTORY_POSITION { string position_id PK  string sku  int available  int reserved  int safety_stock }
    KNOWLEDGE_DOCUMENT { string doc_id PK  string status  string sha256 }
    METRIC_BINDING { string binding_id PK  string type  string schedule  string last_status }
    BIZ_SHOP { string shop_id PK  string platform  string site }
    SYS_ORG { string org_id PK }
    SYS_USER { string user_id PK  string org_id }
""")
