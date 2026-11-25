# -*- coding: utf-8 -*-
"""图 1：智能问数主链路业务流程图 flow-qa-main"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from svglib import SVG, C, export, write_mmd

W, H = 1600, 690
s = SVG(W, H,
        title="图 flow-qa-main　智能问数主链路与异常分支",
        subtitle="对应 FR-QA-12~27。五段式：解析范围 → 口径与计划 → 只读取数 → 质量核验 → 答案与证据；"
                 "任一段失败即在该段显式终止并返回状态，不静默补数、不以 0 代替。")

CX = [200, 480, 760, 1040, 1300]
BW = [220, 220, 240, 180, 220]
TOP, BH = 214, 92

s.text(24, 74, "触发：用户在问数工作台提交自然语言问题（携带会话 ID）。", size=10.5, fill=C["sub"], weight="bold")
s.text(24, 92, "前置：用户已登录且 org_id 有效；涉及店铺在其授权范围内；问数服务可用。", size=9.5, fill=C["muted"])

# S0
s.node(24, 112, 300, 54, "S0 提交问题", "自然语言 + 会话 ID", tone="slate", size=11.5, sub_size=9)
s.text(340, 136, "例：各平台近 30 天净利润是多少？ / 那亚马逊近 7 天广告花费呢？", size=9.2, fill=C["muted"])
s.text(340, 152, "入口：输入框、快捷问题、看板 KPI「问数」、异常线索「追问原因」（FR-QA-37）", size=9.2, fill=C["muted"])
s.path("M174,166 L174,190 L200,190 L200,212", stroke="#334155", sw=1.5, marker="ar")

steps = [
    ("S1 解析范围", ["指标 / 时间 / 平台 / 店铺 / 维度槽位", "追问继承与显式覆盖"], "FR-QA-12、13"),
    ("S2 口径与计划", ["别称 → 唯一指标 · 口径版本", "允许工具清单对用户可见"], "FR-QA-17~19"),
    ("S3 只读取数", ["指标快照 / 库存事实 / 口径定义", "受限 SQL 分支（P2，默认关闭）"], "FR-QA-19、20"),
    ("S4 质量核验", ["截止时间 · 完整性", "币种 · 版本"], "FR-QA-25、26"),
    ("S5 答案与证据", ["简答 + 图表 + 明细", "证据链可复制"], "FR-QA-22、23"),
]
for i, (t, subs, tag) in enumerate(steps):
    cx, w = CX[i], BW[i]
    x = cx - w / 2
    s.node(x, TOP, w, BH, "", tone="blue", tag=tag)
    s.text(cx, TOP + 30, t, size=12.5, fill="#1e3a8a", anchor="middle", weight="bold")
    for j, ln in enumerate(subs):
        s.text(cx, TOP + 52 + j * 17, ln, size=9.2, fill="#1d4ed8", anchor="middle")
    if i < 4:
        s.line(x + w + 2, TOP + BH / 2, CX[i + 1] - BW[i + 1] / 2 - 4, TOP + BH / 2,
               stroke="#334155", sw=1.5, marker="ar")

s.line(1412, TOP + BH / 2, 1448, TOP + BH / 2, stroke="#059669", sw=1.6, marker="ar-g")
s.rect(1452, TOP + 14, 128, 64, fill=C["green_bg"], stroke="#10b981", sw=1.2, rx=8)
s.text(1516, TOP + 40, "用户获得", size=10.5, fill="#065f46", anchor="middle", weight="bold")
s.text(1516, TOP + 58, "可核验的答案", size=9.4, fill="#047857", anchor="middle")

# ---------- 分支行 ----------
BR_Y, BR_H = 372, 124
s.line(20, 340, W - 20, 340, stroke="#e2e8f0", sw=1, dash="5 4")
s.text(24, 334, "异常分支：命中即在当期显式返回状态，不进入下一段，也不以“无数据”笼统代替",
       size=9.5, fill="#94a3b8", weight="bold")

def diamond(cx, cy, hw=8, hh=6.5, fill="#fffbeb", stroke="#f59e0b"):
    s.poly([(cx, cy - hh), (cx + hw, cy), (cx, cy + hh), (cx - hw, cy)], fill=fill, stroke=stroke)

# B1 拒绝
b1x, b1w = 80, 236
s.line(CX[0], TOP + BH, CX[0], BR_Y, stroke="#ef4444", sw=1.2, dash="4 3", marker="ar-r")
s.text(CX[0] + 8, BR_Y - 8, "拒绝", size=8.6, fill="#b91c1c")
s.rect(b1x, BR_Y, b1w, BR_H, fill=C["red_bg"], stroke="#fca5a5", sw=1.1, rx=8)
diamond(b1x + 17, BR_Y + 19)
s.text(b1x + 32, BR_Y + 23, "意图与授权判定", size=9.6, fill="#991b1b", weight="bold")
s.text(b1x + 12, BR_Y + 44, "· 写入类：调价 / 预算 / 删除 / 下架", size=8.7, fill="#7f1d1d")
s.text(b1x + 12, BR_Y + 60, "· 店铺或组织不在授权范围", size=8.7, fill="#7f1d1d")
s.text(b1x + 12, BR_Y + 76, "拒绝并说明只读边界与替代入口；", size=8.7, fill="#7f1d1d")
s.text(b1x + 12, BR_Y + 92, "越权不暴露资源是否存在；均写审计。", size=8.7, fill="#7f1d1d")
s.badge(b1x + 12, BR_Y + 112, "WRITE_REJECTED / PERMISSION_DENIED", "red", size=7.6, mono=True)

# B2 澄清
b2x, b2w = 360, 240
s.line(CX[1], TOP + BH, CX[1], BR_Y, stroke="#d97706", sw=1.2, dash="4 3", marker="ar-a")
s.text(CX[1] + 8, BR_Y - 8, "多解", size=8.6, fill="#b45309")
s.rect(b2x, BR_Y, b2w, BR_H, fill=C["amber_bg"], stroke="#fcd34d", sw=1.1, rx=8)
diamond(b2x + 17, BR_Y + 19, fill="#fef3c7")
s.text(b2x + 32, BR_Y + 23, "口径歧义 / 别称多解", size=9.6, fill="#92400e", weight="bold")
s.text(b2x + 12, BR_Y + 44, "列出候选口径、公式与差异，请用户选择；", size=8.7, fill="#78350f")
s.text(b2x + 12, BR_Y + 60, "澄清前不取数、不猜测作答，也不写入记忆。", size=8.7, fill="#78350f")
s.text(b2x + 12, BR_Y + 76, "同一问题两次澄清仍无法唯一确定时，", size=8.7, fill="#78350f")
s.text(b2x + 12, BR_Y + 92, "转为口径反馈工单交由指标管理员处置。", size=8.7, fill="#78350f")
s.badge(b2x + 12, BR_Y + 112, "NEED_CLARIFICATION", "amber", size=7.8, mono=True)

# B3 P2 SQL
b3x, b3w = 640, 240
s.line(CX[2], TOP + BH, CX[2], BR_Y, stroke="#8b5cf6", sw=1.2, dash="4 3", marker="ar")
s.text(CX[2] + 8, BR_Y - 8, "P2 可选", size=8.6, fill="#6d28d9")
s.rect(b3x, BR_Y, b3w, BR_H, fill=C["purple_bg"], stroke="#c4b5fd", sw=1.1, rx=8)
diamond(b3x + 17, BR_Y + 19, fill="#ede9fe", stroke="#8b5cf6")
s.text(b3x + 32, BR_Y + 23, "训练 SQL 分支（P2，默认关闭）", size=9.4, fill="#5b21b6", weight="bold")
s.text(b3x + 12, BR_Y + 44, "仅检索 READY 训练资料生成候选 SQL；", size=8.7, fill="#4c1d95")
s.text(b3x + 12, BR_Y + 60, "单条 SELECT、表白名单、强制 org_id 谓词、", size=8.7, fill="#4c1d95")
s.text(b3x + 12, BR_Y + 76, "行数与超时上限；结果须与指标快照交叉核对。", size=8.7, fill="#4c1d95")
s.text(b3x + 12, BR_Y + 92, "不合规即拒绝执行并说明命中规则。", size=8.7, fill="#4c1d95")
s.badge(b3x + 12, BR_Y + 112, "SQL_LIMIT", "purple", size=7.8, mono=True)

# B4 数据状态
b4x, b4w = 950, 250
s.line(CX[3], TOP + BH, CX[3], BR_Y, stroke="#64748b", sw=1.2, dash="4 3", marker="ar")
s.text(CX[3] + 8, BR_Y - 8, "判定", size=8.6, fill="#475569")
s.rect(b4x, BR_Y, b4w, BR_H, fill=C["slate_bg"], stroke="#cbd5e1", sw=1.1, rx=8)
diamond(b4x + 17, BR_Y + 19, fill="#f8fafc", stroke="#64748b")
s.text(b4x + 32, BR_Y + 23, "数据状态判定（五种，互不替代）", size=9.4, fill="#334155", weight="bold")
for i, (k, v) in enumerate([("ANSWERED", "已核验，可直接回答"),
                            ("PARTIAL", "数据延迟或缺列，标注影响范围"),
                            ("NO_DATA", "范围内确实没有数据，给出可用范围"),
                            ("MIXED_CURRENCY", "多币种无核验汇率，按币种分别展示"),
                            ("UNAVAILABLE", "取数服务故障，给参考号并可重试")]):
    s.text(b4x + 12, BR_Y + 38 + i * 15.6, k, size=7.6, fill="#0f172a",
           family="DejaVu Sans Mono, monospace", weight="bold")
    s.text(b4x + 108, BR_Y + 38 + i * 15.6, v, size=8.2, fill="#475569")

# B5 交付物
b5x, b5w = 1190, 250
s.line(CX[4] + 30, TOP + BH, b5x + 60, BR_Y, stroke="#2563eb", sw=1.2, dash="4 3", marker="ar-b")
s.text(b5x - 34, BR_Y - 8, "输出", size=8.6, fill="#1d4ed8")
s.rect(b5x, BR_Y, b5w, BR_H, fill="#ffffff", stroke="#93c5fd", sw=1.1, rx=8)
s.text(b5x + 12, BR_Y + 20, "每条答案必须同时给出四项（缺任一即视为未完成）",
       size=9.2, fill="#1e3a8a", weight="bold")
for i, it in enumerate(["① 数值与单位（不标注口径不得作为经营结论）",
                        "② 口径名称与版本 · 数据来源 · data_as_of",
                        "③ 质量状态与受影响范围",
                        "④ 图表与可下钻明细，证据链可复制"]):
    s.text(b5x + 12, BR_Y + 42 + i * 17, it, size=8.5, fill="#334155")
s.text(b5x + 12, BR_Y + 112, "导出时口径与截止时间一并带出（FR-QA-23）", size=8, fill="#1d4ed8")

# ---------- 读取说明条 ----------
FY = 566
s.rect(20, FY, W - 40, 62, fill="#fbfdfb", stroke="#d1fae5", sw=1, rx=6)
s.text(36, FY + 24, "读取来源（只读，全部强制 org_id 作用域）", size=9.4, fill="#047857", weight="bold")
s.text(36, FY + 44, "指标口径与版本（定义 / 公式 / 别名 / 生效日期，同店同日多版本取最高）　·　指标快照（GMV / 订单 / 广告 / 净利润 / 质量标记）　·　库存事实（可售 / 预留 / 安全 / 库位）",
       size=8.1, fill="#065f46")
s.text(1080, FY + 32, "P2　另可检索 READY 训练资料，仅用于生成候选 SQL，不训练也不改写任何数值。", size=8.2, fill="#5b21b6")
s.text(36, FY + 56, "数据提供方为指标域与库存域；本模块只消费不快照、不改数、不回写（见 §3 范围与依赖）。", size=8.2, fill="#059669")

s.legend(24, H - 16, [("box", "#eff6ff", "问数服务处理"), ("box", "#fef2f2", "拒绝分支"),
                      ("box", "#fffbeb", "澄清分支"), ("box", "#f5f3ff", "P2 可选分支"),
                      ("box", "#f1f5f9", "数据状态")], size=9.5)

out = os.path.join(os.path.dirname(__file__), "..", "flow-qa-main.svg")
s.save(out)
print(export(out, dpi=165))

write_mmd(os.path.join(os.path.dirname(__file__), "..", "flow-qa-main.mmd"), """
%% 图 flow-qa-main 智能问数主链路与异常分支（Mermaid 源码；成图见 flow-qa-main.svg / .png）
flowchart TD
    S0["S0 提交问题<br/>自然语言 + 会话 ID"] --> S1["S1 解析范围<br/>指标·时间·平台·店铺·维度·追问继承"]
    S1 --> B1{"写入意图 / 越权?"}
    B1 -- 命中 --> R1["WRITE_REJECTED / PERMISSION_DENIED<br/>说明只读边界，越权不暴露资源存在性"]
    B1 -- 通过 --> S2["S2 口径与计划<br/>别称→唯一指标·口径版本·允许工具"]
    S2 --> B2{"口径多解?"}
    B2 -- 是 --> R2["NEED_CLARIFICATION<br/>列出候选口径，澄清前不取数、不写记忆"]
    B2 -- 否 --> S3["S3 只读取数<br/>指标快照/库存/口径定义；受限 SQL（P2）"]
    S3 -.P2 可选.-> R3["单条 SELECT·表白名单·强制 org_id·行数与超时上限<br/>不合规即 SQL_LIMIT"]
    S3 --> S4["S4 质量核验<br/>截止时间·完整性·币种·版本"]
    R3 --> S4
    S4 --> B4{"数据状态"}
    B4 -- "完整" --> S5["S5 答案与证据<br/>简答 + 图表 + 明细 + 证据链"]
    B4 -- "延迟/缺列" --> R4["PARTIAL：标注影响范围，不补 0"]
    B4 -- "范围内无数据" --> R5["NO_DATA：给出可用范围与替代问法"]
    B4 -- "多币种无核验汇率" --> R6["MIXED_CURRENCY：按币种分别展示"]
    B4 -- "取数服务故障" --> R7["UNAVAILABLE：错误参考号 + 可重试"]
    S5 --> O["交付物：① 数值与单位 ② 口径版本/来源/data_as_of ③ 质量状态 ④ 图表与明细"]
    D1[("指标口径与版本")] -.只读.-> S2
    D2[("指标快照 · 库存事实")] -.只读.-> S3
""")
