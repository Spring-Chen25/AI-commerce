# -*- coding: utf-8 -*-
"""图 7：数据流向图 flow-qa-data（左-事实与链路 / 右-约束）"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from svglib import SVG, C, export, write_mmd

W, H = 1620, 880
s = SVG(W, H,
        title="图 flow-qa-data　智能问数数据流向（含四类数据性质的边界）",
        subtitle="对应 BR-QA-08、BR-QA-09、FR-QA-16~26。四类数据性质必须可辨：模拟值、同步指标点、经营快照、训练样例与模型文字。")

# ================= 左：链路与事实 =================
s.rect(24, 74, 1080, 214, fill="#f8fafc", stroke="#e2e8f0", sw=1, rx=8)
s.text(40, 94, "① 上游指标域（不属本模块实现，仅消费其已发布结果）", size=9.6, fill="#334155", weight="bold")
ups = [
    ("指标定义与口径版本", "公式 · 生效日期 · 别名 · 维度", "草稿 / 已发布 / 停用"),
    ("指标数据绑定与同步", "REST / MCP / SIMULATION 三类接入", "手动同步 + 定时调度；失败≠无数据"),
    ("模拟应用系统", "发布模拟接口，返回构造值", "仅用于联调与演示"),
    ("训练资料库", "字段说明 / 口径文档 / SQL 样例", "上传 → 索引中 → READY"),
]
for i, (t, l1, l2) in enumerate(ups):
    x = 40 + i * 262
    s.rect(x, 108, 246, 68, fill="#ffffff", stroke="#cbd5e1", sw=1.1, rx=7, dash="5 3")
    s.text(x + 123, 128, t, size=9.2, fill="#0f172a", anchor="middle", weight="bold")
    s.text(x + 123, 145, l1, size=7.8, fill="#64748b", anchor="middle")
    s.text(x + 123, 161, l2, size=7.6, fill="#94a3b8", anchor="middle")

s.rect(40, 186, 1048, 88, fill="#ffffff", stroke="#e2e8f0", sw=1, rx=6)
s.text(56, 204, "三类接入的语义差异（契约假设，实现属上游）", size=8.8, fill="#334155", weight="bold")
s.text(56, 222, "· REST：按配置周期拉取，返回 JSON，按取值路径提取单一指标值；失败保留上次值并标 DELAYED。", size=7.9, fill="#475569")
s.text(56, 240, "· MCP：按工具调用取得结构化结果；越权或参数不合法时返回显式错误，不得回退为 0。", size=7.9, fill="#475569")
s.text(56, 258, "· SIMULATION：模拟应用返回构造值，仅供联调与演示，进入快照时必须标 SIMULATION 且答案可见。", size=7.9, fill="#475569")

s.rect(24, 300, 1080, 200, fill="#fbfdfb", stroke="#d1fae5", sw=1, rx=8)
s.text(40, 320, "② 组织内事实层（只读；全部查询强制 org_id 作用域）", size=9.6, fill="#047857", weight="bold")
s.rect(40, 334, 500, 148, fill="#ecfdf5", stroke="#10b981", sw=1.3, rx=8)
s.text(56, 356, "指标快照（经营快照）", size=10.2, fill="#065f46", weight="bold")
for i, t in enumerate([
        "GMV / 订单 / 广告花费 / 净利润 / 退款率",
        "每行带：币种 · 质量标记 · data_as_of",
        "同店同日多版本 → 取最高版本",
        "source_type 标明四类数据性质之一"]):
    s.text(56, 378 + i * 19, "· " + t, size=8.4, fill="#065f46")
s.text(56, 462, "质量标记取值：COMPLETE / PARTIAL / NO_DATA / MIXED_CURRENCY", size=8.0, fill="#059669")

s.rect(560, 334, 524, 148, fill="#ecfdf5", stroke="#10b981", sw=1.3, rx=8)
s.text(576, 356, "库存事实", size=10.2, fill="#065f46", weight="bold")
for i, t in enumerate([
        "可售 / 预留 / 安全库存 / 库位 / 店铺",
        "按仓位快照：回答“现在是否低于安全库存”",
        "不是未来缺货预测，不推断售罄概率",
        "snapshot_at 随答案返回"]):
    s.text(576, 378 + i * 19, "· " + t, size=8.4, fill="#065f46")
s.text(576, 462, "低库存判定：可售 < 安全库存（阈值由指标域定义，本模块只读）", size=8.0, fill="#059669")

# 链路
s.rect(24, 528, 1080, 148, fill="#fcfdff", stroke="#dbeafe", sw=1, rx=8)
s.text(40, 548, "③ 问数链路（本模块实现）", size=9.6, fill="#1d4ed8", weight="bold")
chain = [
    ("自然语言问题", "携带会话 ID", 40, 176, "slate"),
    ("解析与计划", "槽位 · 继承 · 工具白名单", 248, 200, "blue"),
    ("只读取数", "工具执行 · org_id 作用域", 480, 200, "blue"),
    ("质量核验", "完整性 / 币种 / 版本", 712, 176, "blue"),
    ("答案与证据", "简答 + 图表 + 明细", 936, 152, "green"),
]
for label, sub, x, w, tone in chain:
    bg = dict(slate="#f1f5f9", blue="#eff6ff", green="#ecfdf5")[tone]
    bd = dict(slate="#94a3b8", blue="#2563eb", green="#10b981")[tone]
    s.rect(x, 566, w, 70, fill=bg, stroke=bd, sw=1.3, rx=8)
    s.text(x + w / 2, 590, label, size=10, fill="#0f172a", anchor="middle", weight="bold")
    s.text(x + w / 2, 607, sub, size=7.8, fill="#475569", anchor="middle")
    s.text(x + w / 2, 624, "本模块实现" if tone != "slate" else "用户输入", size=7.4, fill="#94a3b8", anchor="middle")
for x1, x2 in [(216, 246), (448, 478), (680, 710), (888, 934)]:
    s.line(x1, 601, x2, 601, stroke="#334155", sw=1.4, marker="ar")

# 事实层 → 取数
s.line(290, 483, 290, 500, stroke="#10b981", sw=1.1)
s.path("M290,500 L580,500 L580,564", stroke="#10b981", sw=1.3, marker="ar-g")
s.text(590, 494, "只读查询（取数失败 → UNAVAILABLE；无记录 → NO_DATA）", size=7.8, fill="#047857")

# 输出
s.rect(24, 700, 1080, 150, fill="#fffdf8", stroke="#fde68a", sw=1, rx=8)
s.text(40, 720, "④ 输出与留存（均由本模块写入；原始事实表不被修改）", size=9.6, fill="#92400e", weight="bold")
outs = [
    ("对话记忆", ["仅 ANSWERED / NO_DATA / MIXED_CURRENCY", "最近 8 轮参与上下文，历史最多 20 轮", "单会话 50 轮上限，30 天前清理"], 40, "#fffbeb", "#fcd34d"),
    ("证据摘要", ["口径版本 · 来源 · data_as_of", "工具追踪与耗时 · 明细行引用", "随答案返回，可复制、可导出"], 400, "#ecfdf5", "#10b981"),
    ("查询审计", ["谁、何时、问什么（摘要）", "用了哪个口径与工具、结果状态", "错误与拒绝同样留痕"], 760, "#fef2f2", "#fca5a5"),
]
for label, items, x, bg, bd in outs:
    s.rect(x, 732, 344, 106, fill=bg, stroke=bd, sw=1.1, rx=7)
    s.text(x + 14, 752, label, size=9.2, fill="#0f172a", weight="bold")
    for i, it in enumerate(items):
        s.text(x + 14, 772 + i * 17, "· " + it, size=7.8, fill="#475569")
s.path("M1012,636 L1012,690 L200,690 L200,730", stroke="#f59e0b", sw=1.0, dash="4 3", marker="ar")
s.text(210, 686, "答案落库：记忆、证据、审计三条写入路径互不替代", size=7.8, fill="#b45309")

# ================= 右：约束 =================
s.rect(1124, 74, 470, 202, fill="#ffffff", stroke="#e2e8f0", sw=1, rx=8)
s.text(1140, 94, "四类数据性质的用法边界（BR-QA-02）", size=9.6, fill="#0f172a", weight="bold")
kinds = [
    ("SIMULATION", "模拟值", "#f1f5f9", "#475569", "可展示但必须标注“模拟”，不得作为经营结论"),
    ("SYNC", "同步指标点", "#eff6ff", "#1d4ed8", "来自 REST/MCP 同步，须带同步时间与状态"),
    ("SNAPSHOT", "经营快照", "#ecfdf5", "#047857", "标准化事实，可作为核验结论的主证据"),
    ("TRAINING/LLM", "训练样例与模型文字", "#f5f3ff", "#6d28d9", "只用于解释与候选 SQL，不得产出数字"),
]
y = 108
for code, name, bg, fg, rule in kinds:
    s.rect(1140, y, 438, 36, fill=bg, stroke="#e2e8f0", sw=0.8, rx=5)
    s.text(1150, y + 15, code, size=7.0, fill=fg, family="DejaVu Sans Mono, monospace", weight="bold")
    s.text(1240, y + 15, name, size=8.2, fill="#0f172a", weight="bold")
    s.text(1150, y + 28, rule, size=7.4, fill="#475569")
    y += 40

s.rect(1124, 292, 470, 250, fill="#fffbeb", stroke="#fcd34d", sw=1.1, rx=8)
s.text(1140, 312, "数据语义硬约束（可验收）", size=9.6, fill="#92400e", weight="bold")
rules = [
    ("币种", "跨币种不强行合计；缺经核验汇率返回 MIXED_CURRENCY，并按币种分别展示。"),
    ("缺失", "字段缺失保持空值，不补 0；质量标记 PARTIAL 并写明影响范围。"),
    ("无数据", "NO_DATA：范围内确实没有数据，须给出可用范围与替代问法。"),
    ("不可用", "UNAVAILABLE：取数服务故障，给参考号与重试；不得与 NO_DATA 合并。"),
    ("版本", "同店同日多版本取最高版本，并在证据中回显所用版本号。"),
    ("截止", "每条答案必须带 data_as_of；不得用“最新”描述早于截止时间的数据。"),
]
y = 334
for k, v in rules:
    s.text(1140, y, k, size=8.0, fill="#78350f", weight="bold")
    yy = s.para(1172, y, v, 400, size=7.8, fill="#78350f", lh=1.4)
    y = max(yy, y + 16) + 8

s.rect(1124, 558, 470, 126, fill="#f5f3ff", stroke="#c4b5fd", sw=1, rx=8)
s.text(1140, 578, "可选解释增强（P1，Vanna 2）", size=9.4, fill="#5b21b6", weight="bold")
for i, t in enumerate([
        "· 只读取已核验结果的数值，不参与计算、不改写数字。",
        "· 超时或不可用回退为规则说明，并标注“解释由规则生成”。",
        "· 不得把训练样例中的历史数字当作本组织当期数值。",
        "· 触发与回退在证据区可见（MODEL_FALLBACK）。"]):
    s.text(1140, 598 + i * 19, t, size=7.9, fill="#4c1d95")

s.rect(1124, 700, 470, 150, fill="#f8fafc", stroke="#cbd5e1", sw=1, rx=8)
s.text(1140, 720, "同步失败的处理链（上游 → 答案）", size=9.4, fill="#334155", weight="bold")
for i, t in enumerate([
        "· 上游同步失败：绑定状态 FAILED / DELAYED，不写入 0，也不删除旧值。",
        "· 快照已过期：查询结果标注 PARTIAL，并给出 data_as_of 与延迟时长。",
        "· 完全无快照记录：NO_DATA，附“可用时间范围”与补数申请入口。",
        "· 取数服务/数据库不可达：UNAVAILABLE，附错误参考号与重试按钮。",
        "· 上述四种都必须在答案正文可见，不得只在日志里出现。"]):
    s.text(1140, 740 + i * 20, t, size=7.8, fill="#475569")

s.text(24, H - 14, "说明：本图为概念级数据流，不表达物理存储、调度实现与字段级 Schema（见详细设计）。",
       size=8.6, fill=C["muted"])

out = os.path.join(os.path.dirname(__file__), "..", "flow-qa-data.svg")
s.save(out)
print(export(out, dpi=160))

write_mmd(os.path.join(os.path.dirname(__file__), "..", "flow-qa-data.mmd"), """
%% 图 flow-qa-data 智能问数数据流向（Mermaid 源码；成图见 flow-qa-data.svg / .png）
flowchart LR
    subgraph UP["① 上游指标域（不属本模块实现）"]
      A1["指标定义与口径版本"]
      A2["指标数据绑定与同步<br/>REST / MCP / SIMULATION"]
      A3["模拟应用系统"]
      A4["训练资料库（READY）"]
    end
    subgraph FACT["② 组织内事实层（只读，org_id 隔离）"]
      B1[("指标快照<br/>币种·质量标记·data_as_of·source_type")]
      B2[("库存事实<br/>可售/预留/安全库存/库位")]
    end
    subgraph QA["③ 问数链路（本模块实现）"]
      C1["自然语言问题"] --> C2["解析与计划"] --> C3["只读取数"] --> C4["质量核验"] --> C5["答案与证据"]
    end
    subgraph OUT["④ 输出与留存"]
      D1["对话记忆（仅三态）"]
      D2["证据摘要"]
      D3["查询审计"]
    end
    A1 -->|已发布口径| B1
    A2 -->|同步结果| B1
    A3 -.->|模拟值，标注 SIMULATION| B1
    B1 --> C3
    B2 --> C3
    A4 -.->|仅生成候选 SQL（P2）| C3
    C5 --> D1
    C5 --> D2
    C5 --> D3
    C5 -.-> V["Vanna 2 解释增强（P1）：不改写数字，超时回退"]

    %% 四类数据性质：SIMULATION / SYNC / SNAPSHOT / TRAINING-LLM
    %% 硬约束：跨币种不合计；缺失不补 0；NO_DATA ≠ UNAVAILABLE；同日多版本取最高；答案必须带 data_as_of
""")
