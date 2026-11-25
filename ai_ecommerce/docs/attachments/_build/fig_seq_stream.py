# -*- coding: utf-8 -*-
"""图 4：流式回答时序图 sequence-qa-stream"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from svglib import SVG, C, export, write_mmd

W, H = 1560, 1010
s = SVG(W, H,
        title="图 sequence-qa-stream　流式回答时序（POST /bi/query/stream，NDJSON）",
        subtitle="对应 FR-QA-07、FR-QA-27~29、FR-QA-32、FR-QA-40。先 status，再 plan；有 SQL 才发 sql；随后 answer_delta 增量与完整 result；错误发 error 并带可关联参考号。")

# 参与者
parts = [
    ("用户", "浏览器 / 工作台", 130),
    ("前端", "Vue3 问数页面", 380),
    ("问数接口", "流式端点", 640),
    ("问数编排", "解析 · 计划 · 取数 · 核验", 900),
    ("事实库", "快照 / 库存（只读）", 1170),
    ("可选 Vanna 2", "解释增强（P1）", 1430),
]
LIFE_TOP, LIFE_BOT = 148, 918
for name, sub, cx in parts:
    s.rect(cx - 92, 92, 184, 48, fill="#eff6ff" if name != "事实库" and "Vanna" not in name else "#ecfdf5",
           stroke="#2563eb" if "Vanna" not in name else "#10b981", sw=1.2, rx=7)
    s.text(cx, 112, name, size=10.2, fill="#0f172a", anchor="middle", weight="bold")
    s.text(cx, 128, sub, size=7.8, fill="#64748b", anchor="middle")
    s.line(cx, LIFE_TOP, cx, LIFE_BOT, stroke="#cbd5e1", sw=1, dash="4 4")
    s.rect(cx - 26, LIFE_BOT, 52, 16, fill="#f1f5f9", stroke="#e2e8f0", sw=0.8, rx=3)

P = {k: v for k, (_, _, v) in zip(["u", "f", "api", "orc", "db", "vn"], parts)}

Y = 176


def msg(y, frm, to, label, ret=False, tone="#334155", note=None, dash=None):
    x1, x2 = P[frm], P[to]
    if ret:
        s.line(x1, y, x2, y, stroke=tone, sw=1.2, dash=dash or "5 3", marker="ar")
    else:
        s.line(x1, y, x2, y, stroke=tone, sw=1.3, dash=dash, marker="ar")
    s.text((x1 + x2) / 2, y - 6, label, size=8.6, fill=tone, anchor="middle")
    if note:
        s.text((x1 + x2) / 2, y + 12, note, size=7.6, fill="#94a3b8", anchor="middle")


def self_msg(y, who, label, tone="#334155", h=34):
    cx = P[who]
    s.path(f"M{cx},{y} L{cx + 60},{y} L{cx + 60},{y + h} L{cx + 2},{y + h}",
           stroke=tone, sw=1.2, marker="ar")
    s.text(cx + 66, y + 10, label, size=8.4, fill=tone)
    return y + h


def frame(y1, y2, label, tone="#dbeafe", frm=380, to=1440):
    s.rect(frm, y1, to - frm, y2 - y1, fill=tone, stroke="none", sw=0, rx=4, opacity=0.55)
    s.text(frm + 8, y1 + 13, label, size=8.2, fill="#1e3a8a", weight="bold")


# 1 提交
msg(Y, "u", "f", "① 输入问题并回车（携带会话 UUID）")
Y += 26
msg(Y, "f", "api", "② POST /bi/query/stream　{question, session_id}",
    note="携带 request_id，断线重连可取回同一 result，不重复取数")
Y += 44
frame(Y - 10, Y + 112, "阶段 1｜解析与计划（服务端同步完成，先回 status）")
msg(Y, "api", "orc", "③ 建立流式上下文并转交编排")
Y += 26
Y = self_msg(Y, "orc", "召回最近 8 轮上下文 → 槽位解析 → 意图与授权判定")
Y += 8
msg(Y, "api", "f", "④ status：{stage: PARSING→RUNNING, session_id, request_id}", ret=False, tone="#2563eb")
Y += 26
msg(Y, "api", "f", "⑤ plan：{metric, 口径版本, 时间, 平台, 店铺, 维度, tools[]}", tone="#2563eb")
Y += 30

frame(Y - 8, Y + 150, "阶段 2｜只读取数（按工具白名单顺序执行，逐个回报进度）")
msg(Y, "orc", "db", "⑥ 只读查询（强制 org_id 谓词 + 授权店铺集合）")
s.text((P["orc"] + P["db"]) / 2, Y + 12, "同日多版本 → 取最高版本；跨币种不合计", size=7.6, fill="#94a3b8", anchor="middle")
Y += 26
msg(Y, "db", "orc", "⑦ 事实行 + data_as_of + 质量标记", ret=True, tone="#059669")
Y += 26
msg(Y, "orc", "db", "⑧ 库存 / 低库存查询（可售、预留、安全库存）", dash="6 4")
Y += 26
msg(Y, "db", "orc", "⑨ 库存事实 + 快照时间", ret=True, tone="#059669")
Y += 34

frame(Y - 10, Y + 184, "阶段 3｜质量核验与答案组织")
Y = self_msg(Y, "orc", "质量核验：完整性 / 延迟 / 币种 / 版本 → 判定 ANSWERED / PARTIAL / NO_DATA / MIXED_CURRENCY / UNAVAILABLE", tone="#475569")
Y += 10
msg(Y, "orc", "vn", "⑩ 可选：请求解释增强（超时即降级，不阻塞数值）", tone="#8b5cf6")
Y += 24
msg(Y, "vn", "orc", "⑪ 解释文本 / 超时 → 规则回退并标注", ret=True, tone="#8b5cf6", dash="5 3")
Y += 30
msg(Y, "api", "f", "⑫ answer_delta × N：增量文本片段", tone="#2563eb")
Y += 26
msg(Y, "api", "f", "⑬ result：答案 + 图表数据 + 明细 + 证据链 + quality_status + data_as_of", tone="#2563eb")

Y += 34
frame(Y - 8, Y + 96, "阶段 4｜记忆与留痕（仅三类终态写会话表）", tone="#fef9c3", frm=380, to=1440)
msg(Y, "orc", "db", "⑭ 若终态 ∈ {ANSWERED, NO_DATA, MIXED_CURRENCY}：写入轮次与证据摘要", tone="#a16207")
Y += 26
Y = self_msg(Y, "orc", "写审计：谁、何时、问什么、用了哪个口径与工具、结果状态与耗时", tone="#a16207", h=26)
Y += 12
msg(Y, "api", "f", "⑮ done：{status, quality_status, tokens, elapsed_ms, audit_ref}", tone="#a16207")

# 异常与中断（右下角注释）
s.rect(60, 830, 700, 150, fill="#fffdf5", stroke="#fcd34d", sw=1, rx=7)
s.text(76, 850, "异常与中断约定", size=9.4, fill="#92400e", weight="bold")
notes = [
    "· error 事件必须在 result 之前发出，携带 {code, message, request_id, retryable}，前端展示可关联参考号。",
    "· 前端主动取消（用户关闭页面 / 点停止）：服务端停止取数并落 ABORTED，已发出的 answer_delta 保留在界面。",
    "· 网络中断但服务端已完成：复用 request_id 重连可拿回同一 result，不重复计费、不重复写会话。",
    "· 取数超时：先重试一次；仍失败给 UNAVAILABLE 与重试入口，绝不返回空答案或 0。",
    "· 事件顺序不可颠倒：status 必为首个事件，result 与 error 互斥，done 必为最后一个事件。",
]
for i, n in enumerate(notes):
    s.text(76, 870 + i * 21, n, size=8.2, fill="#78350f")

s.rect(800, 830, 700, 150, fill="#f8fbff", stroke="#bfdbfe", sw=1, rx=7)
s.text(816, 850, "事件契约要点（字段级 Schema 见详细设计）", size=9.4, fill="#1e3a8a", weight="bold")
fields = [
    "status　stage / session_id / request_id / 已召回上下文条数",
    "plan　　指标、口径版本、时间范围、平台、店铺、维度、工具清单",
    "sql?　　仅 P2 分支出现，携带校验结论（通过 / 拒绝原因）",
    "answer_delta　纯文本增量，不含数字格式化以外的修饰",
    "result　结构：summary、charts[]、table、evidence{口径, 来源, data_as_of, 工具耗时}",
    "error　code / message / request_id / retryable",
]
for i, n in enumerate(fields):
    s.text(816, 870 + i * 19, n, size=8.2, fill="#334155")

out = os.path.join(os.path.dirname(__file__), "..", "sequence-qa-stream.svg")
s.save(out)
print(export(out, dpi=160))

write_mmd(os.path.join(os.path.dirname(__file__), "..", "sequence-qa-stream.mmd"), """
%% 图 sequence-qa-stream 流式回答时序（Mermaid 源码；成图见 sequence-qa-stream.svg / .png）
sequenceDiagram
    autonumber
    participant U as 用户
    participant F as 前端（Vue3 问数页）
    participant A as 问数接口 /bi/query/stream
    participant O as 问数编排
    participant D as 事实库（只读）
    participant V as 可选 Vanna 2

    U->>F: 输入问题并回车（携带会话 UUID）
    F->>A: POST /bi/query/stream {question, session_id, request_id}
    A->>O: 建立流式上下文
    O->>O: 召回最近 8 轮 → 槽位解析 → 意图与授权判定
    A-->>F: status {stage: PARSING→RUNNING}
    A-->>F: plan {metric, 口径版本, 时间, 平台, 店铺, 维度, tools[]}
    O->>D: 只读查询（强制 org_id + 授权店铺集合）
    D-->>O: 事实行 + data_as_of + 质量标记
    O->>D: 库存 / 低库存查询
    D-->>O: 库存事实 + 快照时间
    O->>O: 质量核验 → ANSWERED / PARTIAL / NO_DATA / MIXED_CURRENCY / UNAVAILABLE
    O-)V: 可选解释增强（超时即降级，不阻塞数值）
    V--)O: 解释文本 / 超时 → 规则回退并标注
    A-->>F: answer_delta × N
    A-->>F: result {答案, 图表, 明细, evidence, quality_status, data_as_of}
    alt 终态 ∈ {ANSWERED, NO_DATA, MIXED_CURRENCY}
        O->>D: 写入轮次与证据摘要（记忆）
    else 其他终态
        O->>O: 只写审计，不写记忆
    end
    A-->>F: done {status, quality_status, elapsed_ms, audit_ref}
    Note over A,F: 异常：error 事件在 result 前发出，带 request_id 与 retryable；<br/>网络中断可凭 request_id 重连取回同一 result，不重复取数。
""")
