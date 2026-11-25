# -*- coding: utf-8 -*-
"""图 3：用例图 usecase-qa"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from svglib import SVG, C, export, write_mmd

W, H = 1560, 900
s = SVG(W, H,
        title="图 usecase-qa　智能问数 Agent（M3 / QA）用例图",
        subtitle="对应 UC-QA-01~12。系统边界内为本模块承担的行为；虚线框外为上游指标域职责，本模块只依赖其已发布结果。")

# 系统边界
s.rect(232, 112, 1092, 700, fill="#fcfdff", stroke="#93c5fd", sw=1.4, rx=10, dash=None)
s.text(250, 134, "智能问数 Agent（M3 / QA）· 只读", size=11.5, fill="#1e3a8a", weight="bold")

# 分组底纹
groups = [
    ("① 看板与提问", 250, 150, 340, 300, "#f8fbff"),
    ("② 答案、证据与明细", 610, 150, 340, 300, "#fbfdff"),
    ("③ 会话与留痕", 970, 150, 335, 300, "#fdfdff"),
    ("④ 异常与边界处理", 250, 470, 340, 316, "#fffdfa"),
    ("⑤ 可选 P2 分支", 610, 470, 340, 316, "#fdfaff"),
    ("⑥ 治理入口（本模块只读展示）", 970, 470, 335, 316, "#fbfdfb"),
]
for name, x, y, w, h, bg in groups:
    s.rect(x, y, w, h, fill=bg, stroke="#e6edf6", sw=1, rx=8)
    s.text(x + 12, y + 20, name, size=9.4, fill="#475569", weight="bold")


def oval(cx, cy, label, w=196, tone="blue", p2=False):
    pal = dict(blue=("#eff6ff", "#2563eb", "#1e3a8a"),
               green=("#ecfdf5", "#10b981", "#065f46"),
               amber=("#fffbeb", "#f59e0b", "#92400e"),
               red=("#fef2f2", "#ef4444", "#991b1b"),
               purple=("#f5f3ff", "#8b5cf6", "#5b21b6"),
               slate=("#f8fafc", "#94a3b8", "#334155"))
    bg, bd, tc = pal[tone]
    h = 46
    s.ellipse(cx, cy, w / 2, h / 2, fill=bg, stroke=bd, sw=1.2)
    lines = label.split("\n")
    if len(lines) == 1:
        s.text(cx, cy + 4, lines[0], size=9.6, fill=tc, anchor="middle")
    else:
        s.text(cx, cy - 3, lines[0], size=9.6, fill=tc, anchor="middle", weight="bold")
        s.text(cx, cy + 12, lines[1], size=8.4, fill=tc, anchor="middle")
    return (cx, cy, w / 2, h / 2)


def dashed_arrow(x1, y1, x2, y2, label, above=True):
    s.line(x1, y1, x2, y2, stroke="#7c3aed", sw=1.1, dash="5 3", marker="ar")
    mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    s.text(mx, my - 5 if above else my + 12, label, size=7.8, fill="#6d28d9", anchor="middle")


# ① 看板与提问
o1 = oval(420, 200, "查看经营看板\n7 / 30 / 90 天 · KPI 与趋势")
o2 = oval(420, 276, "自然语言问数\n指标 / 时间 / 平台 / 店铺", w=210)
o3 = oval(420, 352, "连续追问（继承筛选）", w=196)
o4 = oval(420, 422, "查看指标口径与定义", w=190)

# ② 答案、证据与明细
o5 = oval(780, 200, "获得结构化答案\n简答 + 图表 + 明细", w=210)
o6 = oval(780, 276, "展开证据链", w=180, tone="green")
o7 = oval(780, 352, "下钻明细与导出", w=190, tone="green")
o8 = oval(780, 422, "澄清口径（多解时）", w=190, tone="amber")

# ③ 会话与留痕
o9 = oval(1136, 200, "会话恢复 / 新建 / 删除", w=210)
o10 = oval(1136, 276, "查看历史轮次与记忆范围", w=226)
o11 = oval(1136, 352, "对回答反馈（准确 / 有问题）", w=232)
o12 = oval(1136, 422, "查询审计记录（只读）", w=200, tone="slate")

# ④ 异常与边界
o13 = oval(420, 530, "写人类请求被拒绝", w=196, tone="red")
o14 = oval(420, 606, "越权店铺 / 跨组织被拒绝", w=214, tone="red")
o15 = oval(420, 682, "无数据 / 多币种 / 服务不可用\n分别报告", w=248, tone="amber")
o16 = oval(420, 758, "流式中断与重试", w=180, tone="slate")

# ⑤ P2
o17 = oval(780, 530, "训练 SQL 分支（P2）\n默认关闭", w=210, tone="purple")
o18 = oval(780, 618, "候选 SQL 只读校验与执行", w=232, tone="purple")
o19 = oval(780, 700, "与指标快照交叉核对", w=204, tone="purple")
o20 = oval(780, 768, "SQL 校验记录查看", w=190, tone="purple")

# ⑥ 治理入口（只读展示）
o21 = oval(1136, 530, "查看指标快照与质量", w=210, tone="green")
o22 = oval(1136, 606, "查看训练资料状态 READY", w=216, tone="green")
o23 = oval(1136, 690, "查看模拟应用与绑定状态", w=226, tone="green")
o24 = oval(1136, 764, "按授权范围取数\norg_id + 店铺集合", w=222, tone="slate")

# 关系
pairs = [(o2, o3), (o3, o4), (o5, o6), (o5, o7), (o2, o5), (o4, o8), (o17, o18), (o18, o19)]
# 简化：仅画有语义的 include / extend
dashed_arrow(465, 298, 470, 328, "«extend»")     # 追问 extend 问数
dashed_arrow(770, 224, 772, 252, "«include»")      # 答案 include 证据链
s.line(516, 340, 690, 300, stroke="#7c3aed", sw=1.1, dash="5 3", marker="ar")
s.text(556, 330, "«include» 解析继承", size=7.4, fill="#6d28d9")
s.line(510, 408, 686, 422, stroke="#7c3aed", sw=1.0, dash="5 3", marker="ar")
s.text(536, 402, "«include» 口径命中", size=7.4, fill="#6d28d9")
dashed_arrow(776, 594, 776, 554, "«include»")

# 角色
s.actor(120, 262, "运营分析人员", "提问、追问、看数")
s.actor(120, 500, "仓储 / 商品运营", "库存与低库存")
s.actor(120, 700, "指标与知识管理员", "口径答疑、资料维护")
s.actor(1450, 300, "管理者", "看结论与趋势")
s.actor(1450, 560, "系统管理员", "组织、留痕、审计")
s.actor(1450, 760, "审计 / 合规", "留痕复核")

# 角色连线（简化为连到系统边界，避免长斜线穿越用例）
role_lines = [
    ((152, 262), (232, 240)), ((152, 500), (232, 560)), ((152, 700), (232, 700)),
    ((1418, 300), (1472, 240)), ((1418, 560), (1472, 560)), ((1418, 760), (1472, 760)),
]
for (x1, y1), (x2, y2) in role_lines:
    s.line(x1, y1, x2, y2, stroke="#cbd5e1", sw=0.9)
s.text(1240, 884, "角色与用例对应见 §5.1", size=7.6, fill="#94a3b8", anchor="end")

# 上游依赖框（系统边界外）
s.rect(232, 832, 1092, 44, fill="#f8fafc", stroke="#cbd5e1", sw=1, rx=7, dash="5 4")
s.text(248, 852, "上游（不属本模块实现）：指标定义与版本维护、指标数据绑定与同步调度、模拟应用发布、训练资料上传与索引",
       size=8.6, fill="#475569")
s.text(248, 868, "本模块对上述能力只「读取已发布结果」；归属与接口契约见 §2.3 与 TBD-QA-01。", size=8.2, fill="#94a3b8")

s.legend(24, 892, [("line", "#7c3aed", "«include» / «extend»"), ("line", "#cbd5e1", "参与者参与的用例"),
                   ("box", "#eff6ff", "本模块 P0 用例"), ("box", "#f5f3ff", "P2 可选"),
                   ("box", "#ecfdf5", "只读展示 / 证据")], size=8.6)

out = os.path.join(os.path.dirname(__file__), "..", "usecase-qa.svg")
s.save(out)
print(export(out, dpi=160))

write_mmd(os.path.join(os.path.dirname(__file__), "..", "usecase-qa.mmd"), """
%% 图 usecase-qa 智能问数用例图（Mermaid 源码；成图见 usecase-qa.svg / .png）
flowchart LR
    A1((运营分析人员)) --> U1["查看经营看板 7/30/90"]
    A1 --> U2["自然语言问数"]
    A1 --> U3["连续追问（继承筛选）"]
    A1 --> U4["查看指标口径与定义"]
    A1 --> U5["获得结构化答案"]
    A2((仓储 / 商品运营)) --> U6["查询 SKU 库存与低库存"]
    A2 --> U7["下钻明细与导出"]
    A3((指标与知识管理员)) --> U4
    A3 --> U8["澄清口径（多解时）"]
    A3 --> U9["查看训练资料状态"]
    M1((管理者)) --> U1
    M1 --> U5
    S1((系统管理员)) --> U10["会话恢复 / 新建 / 删除"]
    S1 --> U11["查询审计记录（只读）"]
    E1((审计 / 合规)) --> U11

    U3 -.->|«extend»| U2
    U2 -.->|«include»| U12["解析指标 / 时间 / 平台 / 店铺"]
    U5 -.->|«include»| U13["证据链：口径 / 来源 / data_as_of / 质量"]
    U5 -.->|«include»| U14["图表与可下钻明细"]
    U8 -.->|«extend»| U2
    U15["训练 SQL 分支（P2）"] -.->|«extend»| U2
    U15 -.->|«include»| U16["单条只读 SQL 校验"]
    U17["写人类请求"] -.->|被拒绝| U18["WRITE_REJECTED"]
    U19["越权店铺 / 跨组织"] -.->|被拒绝| U20["PERMISSION_DENIED"]

    subgraph UP["上游指标域（不属本模块实现，仅读取已发布结果）"]
      D1["指标定义与版本维护"]
      D2["指标数据绑定与同步调度"]
      D3["模拟应用发布"]
      D4["训练资料上传与索引"]
    end
""")
