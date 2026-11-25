# -*- coding: utf-8 -*-
"""图 2：问答状态机 flow-qa-states（轮次状态 + 质量状态）——四列布局"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from svglib import SVG, C, export, write_mmd

W, H = 1520, 700
s = SVG(W, H,
        title="图 flow-qa-states　一次问数轮次的状态迁移（轮次状态 × 质量状态）",
        subtitle="对应 FR-QA-25、26、32、36。轮次状态回答“这一问有没有被处理完”，质量状态回答“这一问的数据能不能用来下结论”，两者并存、不可互相替代。")

s.rect(20, 70, 980, 588, fill="#fcfdff", stroke="#e6edf6", sw=1, rx=6)
s.text(40, 94, "A. 轮次状态（服务可执行到的阶段）", size=12, fill="#1e3a8a", weight="bold")
s.text(40, 112, "每条轮次写入会话表前必须有唯一终态；仅 ANSWERED / NO_DATA / MIXED_CURRENCY 进入对话记忆。",
       size=8.6, fill=C["muted"])

BORDER = {"green": "#10b981", "amber": "#f59e0b", "slate": "#94a3b8", "red": "#ef4444", "blue": "#2563eb"}
FILL = {"green": C["green_bg"], "amber": C["amber_bg"], "slate": C["slate_bg"], "red": C["red_bg"], "blue": C["blue_bg"]}
MK = {"green": "ar-g", "red": "ar-r", "slate": "ar", "amber": "ar-a", "blue": "ar-b"}


def nd(x, y, w, h, code, label, tone, reason=None):
    s.rect(x, y, w, h, fill=FILL[tone], stroke=BORDER[tone], sw=1.2, rx=7)
    s.text(x + w / 2, y + 17, label, size=9.6, fill="#0f172a", anchor="middle", weight="bold")
    s.text(x + w / 2, y + 31, code, size=7.4, fill="#475569", anchor="middle",
           family="DejaVu Sans Mono, monospace")
    if reason:
        s.text(x + w / 2, y + 44, reason, size=7.4, fill="#64748b", anchor="middle")


# 列 1：解析期直接收敛的两个终态（与右侧同属 turn_status）
nd(46, 150, 190, 44, "NEED_CLARIFICATION", "待用户澄清口径", "amber")
nd(46, 214, 190, 44, "WRITE_REJECTED", "写入类请求被拒绝", "red")
s.text(141, 276, "解析期即收敛，不进入取数", size=7.6, fill="#94a3b8", anchor="middle")

# 列 2：处理链
nd(300, 168, 200, 46, "PARSING", "解析与计划", "blue")
nd(300, 240, 200, 46, "RUNNING", "只读取数 · 质量核验", "blue")
s.line(400, 214, 400, 238, stroke="#334155", sw=1.4, marker="ar")
s.text(408, 232, "计划就绪", size=8.0, fill="#64748b")

# 列 2 分叉出两个解析期终态（向左），并从上方回流
s.path("M300,190 L262,190 L262,172 L238,172", stroke="#d97706", sw=1.3, marker="ar-a")
s.text(268, 164, "口径多解", size=7.6, fill="#b45309", anchor="middle")
s.path("M300,244 L262,244 L262,236 L238,236", stroke="#ef4444", sw=1.3, marker="ar-r")
s.text(268, 258, "写入意图", size=7.6, fill="#b91c1c", anchor="middle")
# 澄清后回流
s.path("M46,150 L26,150 L26,120 L400,120 L400,164", stroke="#d97706", sw=1.1, dash="4 3", marker="ar-a")
s.text(150, 134, "用户补充口径后重新解析（同一会话）", size=7.8, fill="#b45309", anchor="middle")

# 列 3：终态
terms = [
    ("ANSWERED", "已核验回答", "green", "质量完整", True),
    ("NO_DATA", "范围内无数据", "green", "范围内无数据", True),
    ("MIXED_CURRENCY", "多币种不合计", "green", "多币种无核验汇率", True),
    ("UNAVAILABLE", "取数服务故障", "red", "重试后仍失败", False),
    ("PERMISSION_DENIED", "越权请求被拒绝", "red", "授权校验不通过", False),
    ("ABORTED", "客户端中断 / 断流", "slate", "传输未完成", False),
]
TX, TW, ROW0, GAP, TH = 536, 236, 150, 64, 50
TRK = 508
s.line(502, 263, TRK, 263, stroke="#334155", sw=1.4)
s.line(TRK, 150 + TH / 2, TRK, ROW0 + 5 * GAP + TH / 2, stroke="#cbd5e1", sw=1.2)
for i, (code, label, tone, why, mem) in enumerate(terms):
    y = ROW0 + i * GAP
    cy = y + TH / 2
    nd(TX, y, TW, TH, code, label, tone, why)
    s.line(TRK, cy, TX - 2, cy, stroke=BORDER[tone], sw=1.3, marker=MK[tone])
    s.badge(TX + TW + 14, cy, "进入记忆" if mem else "不记忆",
            "green" if mem else "slate", size=7.2)

# 记忆说明
s.rect(834, 130, 152, 404, fill="#ffffff", stroke="#e2e8f0", sw=0.8, rx=6, dash="4 3")
s.text(910, 144, "记忆策略（FR-QA-32）", size=8.2, fill=C["muted"], anchor="middle")
for i, ln in enumerate(["· 三态记忆：仅 ANSWERED、", "  NO_DATA、MIXED_CURRENCY",
                        "· 最近 8 轮参与上下文", "· 历史查询最多返回 20 轮",
                        "· 单会话上限 50 轮", "· 30 天前记录定期清理"]):
    s.text(846, 168 + i * 15, ln, size=7.4, fill="#475569")
for i, ln in enumerate(["· 拒绝 / 澄清 / 越权 / 故障 /", "  断流五类不入记忆，", "  仅写审计（FR-QA-40）"]):
    s.text(846, 268 + i * 15, ln, size=7.4, fill="#b91c1c")
for i, ln in enumerate(["· 断流不改变服务端终态；", "  前端保留已收片段，", "  不伪装为完整结果", "· 被拒绝的写入请求不作为", "  后续追问的上下文", "· 澄清超时未答复按", "  ABORTED 收敛，不得自行", "  选择口径继续作答"]):
    s.text(846, 330 + i * 15, ln, size=7.4, fill="#475569")

# 补充约定
s.rect(24, 512, 460, 94, fill="#ffffff", stroke="#e2e8f0", sw=1, rx=6)
s.text(38, 532, "状态与文案要求", size=9.0, fill="#334155", weight="bold")
s.text(38, 550, "① 终态必须写入会话表与审计，用户侧看到同一状态码与同一套中文解释，不出现“同错不同文”。", size=8.2, fill="#475569")
s.text(38, 566, "② 状态判定条件、阈值与文案逐条验收（AC-QA-05~09）；任何分支都不得以空答案或 0 代替。", size=8.2, fill="#475569")
s.text(38, 582, "③ 状态枚举新增或重命名属需求变更，须同步更新本节、FR-QA-25 与追溯表。", size=8.2, fill="#475569")
s.text(38, 596, "④ NEED_CLARIFICATION 与 WRITE_REJECTED 在解析期直接收敛，同属 turn_status。", size=8.2, fill="#475569")

# ---------- 右：质量状态 ----------
s.rect(1016, 70, 484, 588, fill="#fbfdff", stroke="#e6edf6", sw=1, rx=6)
s.text(1036, 94, "B. 质量状态（答案里的数据能不能用）", size=12, fill="#1e3a8a", weight="bold")
s.text(1036, 112, "随答案返回并可下钻到具体数据源；不得用“暂无数据”合并不同语义。",
       size=8.6, fill=C["muted"])
s.text(1036, 124, "（下列文案中的数值与参考号均为构造示例，仅示意形态，不构成阈值或实现承诺）", size=7.4, fill="#94a3b8")

quality = [
    ("COMPLETE", "green", "所涉指标与维度全部到齐、无延迟。", "可下钻明细；环比同比可计算",
     "示例：五平台指标齐全，可直接比较平台占比"),
    ("PARTIAL", "amber", "部分数据源延迟、缺列，或被上游标记待复核。", "写明受影响范围与时间窗，不补 0",
     "示例：Shopee 结算延迟 2h18m，仅影响 11-12～11-14"),
    ("NO_DATA", "slate", "查询范围内确实没有数据，或字段尚未接入。", "给出可用范围、替代问法与补数申请",
     "示例：德国站未接入退款字段，范围为 US / SG / TH"),
    ("MIXED_CURRENCY", "amber", "涉及多币种且缺少经核验汇率。", "按币种分别展示，不生成合计",
     "示例：USD / CNY / THB 缺核验汇率，分币种展示"),
    ("UNAVAILABLE", "red", "取数服务或可选模型服务故障。", "错误参考号 + 重试入口，不产出推测值",
     "示例：外部数据源超时，参考号形如 QA-7F3A，无推测值"),
]
y = 128
for code, tone, desc, rule, eg in quality:
    s.rect(1034, y, 448, 72, fill="#ffffff", stroke="#e2e8f0", sw=1, rx=7)
    s.rect(1034, y, 5, 72, fill=BORDER[tone], rx=2)
    s.text(1050, y + 18, code, size=8.8, fill="#0f172a", family="DejaVu Sans Mono, monospace", weight="bold")
    s.text(1180, y + 18, desc, size=8.3, fill="#334155")
    s.text(1050, y + 36, "用户可见规则：" + rule, size=8.0, fill="#64748b")
    s.text(1050, y + 52, eg, size=7.6, fill="#94a3b8")
    y += 82

s.rect(1034, 546, 448, 132, fill="#fffbeb", stroke="#fcd34d", sw=1.1, rx=7)
s.text(1050, 566, "组合与优先级（评审待确认 TBD-QA-13）", size=8.8, fill="#92400e", weight="bold")
s.text(1050, 584, "同一答案可能同时命中多条：建议按「UNAVAILABLE > MIXED_CURRENCY >", size=8.0, fill="#78350f")
s.text(1050, 599, "NO_DATA > PARTIAL > COMPLETE」给出主状态，其余作为附注列出；正文措辞", size=8.0, fill="#78350f")
s.text(1050, 614, "由主状态决定，证据区展示由附注决定，二者不得只留其一。", size=8.0, fill="#78350f")
s.text(1050, 632, "质量状态与轮次状态可同时出现（如 ANSWERED + PARTIAL）。", size=8.0, fill="#78350f")
s.text(1050, 652, "展示形态不等于已部署精度，不得以截图宣称准确率（AC-QA-02）。", size=7.8, fill="#b45309")
s.text(1050, 668, "逐条验收见 AC-QA-05~09；界面示意见原型 P08 状态实验室。", size=7.8, fill="#b45309")

s.text(24, H - 14, "说明：终态与状态码命名以本章为准；状态判定规则与用户可见文案均为可验收需求，不得只写“友好提示”。",
       size=8.6, fill=C["muted"])

out = os.path.join(os.path.dirname(__file__), "..", "flow-qa-states.svg")
s.save(out)
print(export(out, dpi=165))

write_mmd(os.path.join(os.path.dirname(__file__), "..", "flow-qa-states.mmd"), """
%% 图 flow-qa-states 轮次状态机与质量状态（Mermaid 源码；成图见 flow-qa-states.svg / .png）
stateDiagram-v2
    [*] --> PARSING
    PARSING --> NEED_CLARIFICATION: 口径多解（不记忆）
    NEED_CLARIFICATION --> PARSING: 用户补充口径
    PARSING --> WRITE_REJECTED: 写入意图（不记忆）
    PARSING --> RUNNING: 计划就绪
    RUNNING --> ANSWERED: 质量完整（记忆）
    RUNNING --> NO_DATA: 范围内无数据（记忆）
    RUNNING --> MIXED_CURRENCY: 多币种无核验汇率（记忆）
    RUNNING --> UNAVAILABLE: 重试后仍失败（不记忆）
    RUNNING --> PERMISSION_DENIED: 授权校验不通过（不记忆）
    RUNNING --> ABORTED: 客户端中断 / 断流（不记忆）
    ANSWERED --> [*]
    NO_DATA --> [*]
    MIXED_CURRENCY --> [*]
    UNAVAILABLE --> [*]
    PERMISSION_DENIED --> [*]
    WRITE_REJECTED --> [*]
    ABORTED --> [*]

%% 质量状态（与轮次状态并行）：COMPLETE / PARTIAL / NO_DATA / MIXED_CURRENCY / UNAVAILABLE
%% 建议优先级：UNAVAILABLE > MIXED_CURRENCY > NO_DATA > PARTIAL > COMPLETE（TBD-QA-13）
""")
