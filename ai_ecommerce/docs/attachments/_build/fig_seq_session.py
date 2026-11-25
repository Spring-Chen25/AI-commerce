# -*- coding: utf-8 -*-
"""图 5：看板加载与会话恢复时序图 sequence-qa-session"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from svglib import SVG, C, export, write_mmd

W, H = 1560, 800
s = SVG(W, H,
        title="图 sequence-qa-session　看板加载、会话恢复与新建会话",
        subtitle="对应 FR-QA-11、FR-QA-30~32、FR-QA-36。进入页面先看事实再对话；会话恢复失败不阻断新问题；“新建会话”只删除问数对话记录，不动原始经营数据。")

parts = [
    ("用户", "浏览器 / 工作台", 120),
    ("前端", "Vue3 问数页面", 360),
    ("看板接口", "GET /bi/dashboard", 610),
    ("会话接口", "GET / DELETE /bi/sessions", 880),
    ("问数编排", "回忆与记忆", 1140),
    ("事实库", "快照 / 库存（只读）", 1410),
]
LIFE_TOP, LIFE_BOT = 148, 632
for name, sub, cx in parts:
    s.rect(cx - 92, 92, 184, 48, fill="#eff6ff", stroke="#2563eb", sw=1.2, rx=7)
    s.text(cx, 112, name, size=10.2, fill="#0f172a", anchor="middle", weight="bold")
    s.text(cx, 128, sub, size=7.8, fill="#64748b", anchor="middle")
    s.line(cx, LIFE_TOP, cx, LIFE_BOT, stroke="#cbd5e1", sw=1, dash="4 4")

P = {k: v for k, (_, _, v) in zip(["u", "f", "dash", "sess", "orc", "db"], parts)}
Y = 180


def msg(y, frm, to, label, ret=False, tone="#334155", note=None, dash=None):
    x1, x2 = P[frm], P[to]
    s.line(x1, y, x2, y, stroke=tone, sw=1.2 if ret else 1.3, dash=dash or ("5 3" if ret else None), marker="ar")
    s.text((x1 + x2) / 2, y - 6, label, size=8.6, fill=tone, anchor="middle")
    if note:
        s.text((x1 + x2) / 2, y + 12, note, size=7.6, fill="#94a3b8", anchor="middle")


def frame(y1, y2, label, tone="#dbeafe"):
    s.rect(336, y1, 1104, y2 - y1, fill=tone, stroke="none", rx=4, opacity=0.5)
    s.text(1432, y1 + 13, label, size=8.2, fill="#1e3a8a", weight="bold", anchor="end")


def self_msg(y, who, label, tone="#334155", h=30):
    cx = P[who]
    s.path(f"M{cx},{y} L{cx + 56},{y} L{cx + 56},{y + h} L{cx + 2},{y + h}",
           stroke=tone, sw=1.2, marker="ar")
    s.text(cx + 62, y + 10, label, size=8.4, fill=tone)
    return y + h


frame(Y - 10, Y + 104, "阶段 1｜进入页面：先看事实，再看对话（看板为问答提供上下文与入口）")
msg(Y, "u", "f", "① 打开「智能问答」页面")
Y += 26
msg(Y, "f", "dash", "② GET /bi/dashboard?days=30", note="并行请求，不阻塞用户输入")
Y += 26
msg(Y, "dash", "db", "③ 读取 KPI / 趋势 / 平台贡献 / 低库存 / 开放异常", dash="6 4")
Y += 26
msg(Y, "dash", "f", "④ 看板数据 + data_as_of + 质量条 + 各卡口径版本", ret=True, tone="#059669")
Y += 34

frame(Y - 10, Y + 100, "阶段 2｜会话恢复（sessionStorage 中的 UUID 是否仍有效）")
s.path("M352,{0} L416,{0} L416,{1} L354,{1}".format(Y, Y + 24), stroke="#334155", sw=1.2, marker="ar")
s.text(424, Y + 8, "⑤ 读取本地 sessionStorage 中的会话 UUID", size=8.6, fill="#334155")
Y += 34
msg(Y, "f", "sess", "⑥ GET /bi/sessions/{id}/turns?limit=20")
Y += 26
msg(Y, "sess", "orc", "⑦ 校验 org_id 与会话归属，召回最近 8 轮参与上下文")
Y += 26
msg(Y, "sess", "f", "⑧ 命中：返回历史轮次（含状态与证据摘要）", ret=True, tone="#059669")
s.text(624, Y + 30, "未命中 / 失效 / 越权：返回 404 或 403，前端提示“会话已失效”，直接开启新会话，不阻断提问",
       size=8.2, fill="#b45309")
Y += 58

frame(Y - 10, Y + 92, "阶段 3｜新建会话（先删除旧对话记录，再生成新 UUID）", tone="#fef9c3")
msg(Y, "u", "f", "⑨ 点击「新建会话」并确认二次确认框", tone="#a16207")
Y += 26
msg(Y, "f", "sess", "⑩ DELETE /bi/sessions/{id}", tone="#a16207", note="仅删除问数轮次、证据摘要与记忆；原始快照与库存不受影响")
Y += 26
msg(Y, "sess", "db", "⑪ 删除范围复核：仅会话表与证据摘要，不触碰事实表", ret=False, tone="#a16207", dash="4 3")
Y += 26
s.path("M352,{0} L416,{0} L416,{1} L354,{1}".format(Y, Y + 24), stroke="#a16207", sw=1.2, marker="ar")
s.text(424, Y + 8, "⑫ 前端生成新 UUID，清空上下文与记忆进度", size=8.6, fill="#a16207")

# 注意区
s.rect(60, 664, 720, 106, fill="#fffdf5", stroke="#fcd34d", sw=1, rx=7)
s.text(76, 686, "失败与边界", size=9.2, fill="#92400e", weight="bold")
for i, t in enumerate([
    "· 看板接口失败：页面照常可提问，看板区显示错误与重试，不以空数据替代 KPI。",
    "· 会话恢复失败不得阻塞新问题；用户仍可立即提问，避免“恢复中转圈”。",
    "· 删除会话为显式确认操作，记录操作人、时间与会话 ID；不支持恢复已删除会话。",
    "· 会话保留 30 天、单会话最多 50 轮（TBD-QA-09 确认清理任务责任人）。",
]):
    s.text(76, 706 + i * 19, t, size=8.1, fill="#78350f")

s.rect(812, 664, 688, 106, fill="#f8fbff", stroke="#bfdbfe", sw=1, rx=7)
s.text(828, 686, "会话态与页面态的区别（易混淆点）", size=9.2, fill="#1e3a8a", weight="bold")
for i, t in enumerate([
    "· 会话 ID 由前端生成并保存（sessionStorage），服务端以 org_id + 会话 ID 双要素校验归属。",
    "· “新建会话”不等于清空数据库：原始经营事实、审计记录、指标快照一律保留。",
    "· 看板 KPI 卡的“问数”按钮携带预设问题进入对话，属于同一会话的普通一轮。",
    "· 组织切换（org_id 变化）必须新建会话，禁止跨组织继承上下文。",
]):
    s.text(828, 706 + i * 19, t, size=8.1, fill="#334155")

out = os.path.join(os.path.dirname(__file__), "..", "sequence-qa-session.svg")
s.save(out)
print(export(out, dpi=160))

write_mmd(os.path.join(os.path.dirname(__file__), "..", "sequence-qa-session.mmd"), """
%% 图 sequence-qa-session 看板加载与会话恢复（Mermaid 源码；成图见 sequence-qa-session.svg / .png）
sequenceDiagram
    autonumber
    participant U as 用户
    participant F as 前端（问数页面）
    participant D as 看板接口
    participant S as 会话接口
    participant O as 问数编排
    participant DB as 事实库

    U->>F: 打开「智能问答」页面
    par 并行加载看板
        F->>D: GET /bi/dashboard?days=30
        D->>DB: 读取 KPI / 趋势 / 平台贡献 / 低库存 / 开放异常
        DB-->>D: 事实行 + data_as_of
        D-->>F: 看板数据 + 质量条 + 口径版本
    and 尝试恢复会话
        F->>F: 读取 sessionStorage 的 UUID
        F->>S: GET /bi/sessions/{id}/turns?limit=20
        S->>O: 校验 org_id 与会话归属
        alt 会话有效
            S-->>F: 历史轮次（状态 + 证据摘要），最近 8 轮参与上下文
        else 失效 / 越权
            S-->>F: 404 / 403，提示“会话已失效”，直接开启新会话
        end
    end
    U->>F: 点击「新建会话」并确认
    F->>S: DELETE /bi/sessions/{id}
    S->>DB: 仅删除问数轮次与证据摘要（不触碰事实表）
    F->>F: 生成新 UUID，清空上下文与记忆进度
    Note over F,S: 看板失败不阻塞提问；删除会话需二次确认并写审计。
""")
