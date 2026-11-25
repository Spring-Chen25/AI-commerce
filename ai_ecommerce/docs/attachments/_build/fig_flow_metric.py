# -*- coding: utf-8 -*-
"""图 8：指标配置主链路 flow-qa-metric"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from svglib import SVG, C, export, write_mmd

W, H = 1620, 786
s = SVG(W, H,
        title="图 flow-qa-metric　指标管理与维护：从“定义指标”到“可以问数”",
        subtitle="对应 FR-QA-42~51、BR-QA-12~16。配置侧可写，运行侧只读；同步是事实数据进入系统的唯一自动通道，人工不能改数。")

steps = [
    ("S1 新建指标", ["编码 · 名称 · 业务定义", "平台 / 维度 / 币种 / 展示规则"], "FR-QA-42", 40, "slate"),
    ("S2 编写口径", ["公式或取数说明", "差异说明 · 生效日期"], "FR-QA-43", 214, "blue"),
    ("S3 维护别名", ["口语叫法 · 平台叫法", "冲突检测 · 批量导入"], "FR-QA-44", 388, "blue"),
    ("S4 创建绑定", ["REST / MCP / SIMULATION", "路径 · 参数 · 频率 · 重试"], "FR-QA-47", 562, "blue"),
    ("S5 绑定测试", ["真实取数或模拟调用", "结论 + 样例值，不落生产快照"], "FR-QA-47", 736, "amber"),
    ("S6 发布口径", ["完整性 + 至少一次成功取数", "发布后不可改，只能新建版本"], "FR-QA-43", 910, "amber"),
    ("S7 同步指标点", ["手动触发 / 定时调度", "失败不写 0，保留旧值"], "FR-QA-49", 1084, "blue"),
    ("S8 可问数", ["进入问数候选集", "口径版本 + data_as_of 可追溯"], "FR-QA-46", 1258, "green"),
]

s.rect(24, 76, 1572, 206, fill="#f8fbff", stroke="#e2e8f0", sw=1, rx=8)
s.text(40, 96, "① 配置主链路（指标管理员执行；每一步都可停在草稿态，不进入问数候选集）", size=9.6, fill="#1e3a8a", weight="bold")

for label, lines, fr, x, tone in steps:
    bg = dict(slate="#f1f5f9", blue="#eff6ff", amber="#fffbeb", green="#ecfdf5")[tone]
    bd = dict(slate="#94a3b8", blue="#2563eb", amber="#d97706", green="#10b981")[tone]
    s.rect(x, 122, 152, 92, fill=bg, stroke=bd, sw=1.3, rx=8)
    s.text(x + 76, 144, label, size=9.6, fill="#0f172a", anchor="middle", weight="bold")
    s.text(x + 76, 162, lines[0], size=7.5, fill="#475569", anchor="middle")
    s.text(x + 76, 177, lines[1], size=7.5, fill="#475569", anchor="middle")
    s.badge(x + 76, 202, fr, tone if tone != "slate" else "slate", size=7.0)

for i in range(len(steps) - 1):
    x1 = steps[i][3] + 152
    x2 = steps[i + 1][3]
    s.line(x1, 168, x2 - 2, 168, stroke="#334155", sw=1.4, marker="ar")

s.rect(24, 296, 1572, 62, fill="#fffdf8", stroke="#fcd34d", sw=1, rx=8)
s.text(40, 316, "发布门槛（BR-QA-14）：口径必填完整 + 维度/平台合法 + 至少一次成功取数或模拟返回。三项缺一，状态停在“待验证”，不可问数。",
       size=8.6, fill="#92400e", weight="bold")
s.text(40, 338, "口径一旦发布即不可修改（BR-QA-13）：调口径必须新建版本，旧版本转“已停用”但永久保留，历史答案按版本生效日期分段复现。",
       size=8.4, fill="#78350f")

s.rect(24, 374, 790, 236, fill="#fbfdfb", stroke="#d1fae5", sw=1, rx=8)
s.text(40, 394, "② 指标状态与守卫（状态由系统计算，人工不可改写）", size=9.6, fill="#047857", weight="bold")
states = [
    ("DRAFT", "草稿", "必填未齐或未测试；不进入问数", "#f8fafc", "#94a3b8"),
    ("PENDING", "待验证", "口径齐但未成功取数/模拟", "#fffbeb", "#d97706"),
    ("READY", "可问数", "已发布 + 最近同步成功", "#ecfdf5", "#10b981"),
    ("DELAYED", "已延迟", "超 2 周期未成功，数据陈旧但仍可用", "#fffbeb", "#d97706"),
    ("FAILED", "同步失败", "持续失败，最近值不可信", "#fef2f2", "#ef4444"),
    ("DISABLED", "已停用", "不可问，历史答案仍可复现，可随时启用", "#f1f5f9", "#64748b"),
    ("DELETED", "已删除（软）", "不删数据，仅不可用；可恢复为已停用", "#fdf4ff", "#a855f7"),
]
y = 412
for code, name, why, bg, bd in states:
    s.rect(40, y, 758, 26, fill=bg, stroke=bd, sw=0.9, rx=5)
    s.text(50, y + 17, code, size=7.6, fill="#0f172a", family="DejaVu Sans Mono, monospace", weight="bold")
    s.text(140, y + 17, name, size=8.6, fill="#0f172a", weight="bold")
    s.text(250, y + 17, why, size=8.0, fill="#475569")
    y += 30

s.rect(830, 374, 766, 236, fill="#fffafa", stroke="#fecaca", sw=1, rx=8)
s.text(846, 394, "③ 同步失败的处置链（BR-QA-16：失败不写 0、不删旧值）", size=9.6, fill="#991b1b", weight="bold")
rows = [
    ("鉴权失效", "连接过期或令牌无效", "去中台重新授权 → 重测绑定 → 手动补数"),
    ("网络 / 超时", "不可达、响应超时", "按配置重试；达上限转人工，保留旧值"),
    ("字段缺失", "取值路径不匹配或缺列", "该指标点标 PARTIAL；修路径后重测"),
    ("平台 4xx/5xx", "对方拒绝或故障", "记错误参考号；与平台侧对账；标 DELAYED"),
    ("格式异常", "返回结构不符合契约", "不落库；记录样例（脱敏）；报缺陷"),
]
y = 416
for a, b, c in rows:
    s.text(846, y, a, size=8.2, fill="#7f1d1d", weight="bold")
    s.text(936, y, b, size=7.9, fill="#7f1d1d")
    s.text(846, y + 15, "→ " + c, size=7.8, fill="#b91c1c")
    y += 39

s.rect(24, 626, 1572, 140, fill="#ffffff", stroke="#e2e8f0", sw=1, rx=8)
s.text(40, 646, "④ 权限与边界", size=9.6, fill="#334155", weight="bold")
cols = [
    ("可写配置的角色（仅两类）", ["指标与知识管理员：指标增删改查、口径、绑定、模拟",
                        "系统管理员（admin）：同上，权限等价，不做双人约束",
                        "数据运营：仅触发同步/重试；其余角色全部只读"]),
    ("明确不提供的入口", ["直接编辑快照数值", "把模拟值“转正”为真实值",
                          "修改已发布的历史口径 / 指标编码", "物理删除（只有软删除）"]),
    ("与其他模块的接缝", ["平台连接与授权 → 数据接入中台", "组织/角色/店铺范围 → 权限中台",
                          "库存事实 → 库存域（只读）", "驾驶舱渲染 → M2"]),
]
x = 40
for title, items in cols:
    s.text(x, 670, title, size=8.8, fill="#1e3a8a", weight="bold")
    for i, it in enumerate(items):
        s.text(x, 690 + i * 18, "· " + it, size=7.9, fill="#475569")
    x += 520

s.text(24, H - 14, "说明：本图为配置侧业务流程，与问数主链路（图 1）通过“可问数”状态衔接；调度周期与失败阈值见 TBD-QA-19。",
       size=8.6, fill=C["muted"])

out = os.path.join(os.path.dirname(__file__), "..", "flow-qa-metric.svg")
s.save(out)
print(export(out, dpi=160))

write_mmd(os.path.join(os.path.dirname(__file__), "..", "flow-qa-metric.mmd"), """
%% 图 flow-qa-metric 指标管理与维护（Mermaid 源码；成图见 flow-qa-metric.svg / .png）
flowchart LR
    A["S1 新建指标<br/>编码·名称·定义·平台/维度/币种/展示规则"] --> B["S2 编写口径<br/>公式·差异说明·生效日期"]
    B --> C["S3 维护别名<br/>口语叫法·冲突检测"]
    C --> D["S4 创建绑定<br/>REST / MCP / SIMULATION"]
    D --> E["S5 绑定测试<br/>真实取数或模拟调用"]
    E -->|失败| E1["停在待验证<br/>不进入问数候选集"]
    E -->|成功| F["S6 发布口径<br/>完整性 + 至少一次成功取数"]
    F --> G["S7 同步指标点<br/>手动 / 定时；失败不写 0"]
    G -->|成功| H["S8 可问数<br/>口径版本 + data_as_of"]
    G -->|连续失败| G1["DELAYED / FAILED<br/>保留旧值，标 PARTIAL"]

    %% 状态：DRAFT / PENDING / READY / DELAYED / FAILED / DISABLED（由系统计算）
    %% 守卫：已发布不可改；有历史引用禁止删除；模拟值带 SIMULATION 且可清除、不可转正
    %% 权限：指标管理员可写配置；数据运营仅同步；运行侧对事实数据只读
""")
