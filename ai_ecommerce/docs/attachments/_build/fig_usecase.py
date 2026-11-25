# -*- coding: utf-8 -*-
"""图 2：用例图 usecase-qa（运行侧 + 配置侧）"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from svglib import SVG, C, export, write_mmd

W, H = 1600, 1090
s = SVG(W, H,
        title="图 usecase-qa　智能问数 Agent（M3 / QA）用例图",
        subtitle="对应 UC-QA-01~21。系统边界内分两域：运行侧（问数，只读）与配置侧（指标管理与维护、绑定同步、模拟应用，可写）；边界外只剩库存域、权限中台与可选模型服务。")

# 系统边界
s.rect(216, 108, 1160, 872, fill="#fcfdff", stroke="#93c5fd", sw=1.4, rx=10)
s.text(234, 130, "智能问数 Agent（M3 / QA）", size=11.5, fill="#1e3a8a", weight="bold")

groups = [
    ("① 看板与提问（运行侧 · 只读）", 236, 146, 348, 292, "#f8fbff"),
    ("② 答案、证据与明细（运行侧）", 600, 146, 358, 292, "#fbfdff"),
    ("③ 会话与留痕（运行侧）", 974, 146, 382, 292, "#fdfdff"),
    ("④ 异常与边界处理", 236, 456, 348, 300, "#fffdfa"),
    ("⑤ 可选 P2 分支", 600, 456, 358, 300, "#fdfaff"),
    ("⑥ 指标管理（配置侧 · 可写）", 974, 456, 382, 300, "#f5faff"),
    ("⑦ 绑定 · 同步 · 模拟应用（配置侧 · 可写）", 236, 782, 720, 190, "#f6fdfa"),
    ("⑧ 指标资产与口径查看（只读）", 974, 772, 382, 196, "#fbfdfb"),
]
for name, x, y, w, h, bg in groups:
    s.rect(x, y, w, h, fill=bg, stroke="#e6edf6", sw=1, rx=8)
    s.text(x + 12, y + 20, name, size=9.4, fill="#475569", weight="bold")


def oval(cx, cy, label, w=196, tone="blue"):
    pal = dict(blue=("#eff6ff", "#2563eb", "#1e3a8a"),
               green=("#ecfdf5", "#10b981", "#065f46"),
               amber=("#fffbeb", "#f59e0b", "#92400e"),
               red=("#fef2f2", "#ef4444", "#991b1b"),
               purple=("#f5f3ff", "#8b5cf6", "#5b21b6"),
               teal=("#e6fffb", "#0d9488", "#115e59"),
               slate=("#f8fafc", "#94a3b8", "#334155"))
    bg, bd, tc = pal[tone]
    h = 46
    s.ellipse(cx, cy, w / 2, h / 2, fill=bg, stroke=bd, sw=1.2)
    lines = label.split("\n")
    if len(lines) == 1:
        s.text(cx, cy + 4, lines[0], size=9.4, fill=tc, anchor="middle")
    else:
        s.text(cx, cy - 3, lines[0], size=9.4, fill=tc, anchor="middle", weight="bold")
        s.text(cx, cy + 12, lines[1], size=8.2, fill=tc, anchor="middle")


def dashed_arrow(x1, y1, x2, y2, label, above=True):
    s.line(x1, y1, x2, y2, stroke="#7c3aed", sw=1.1, dash="5 3", marker="ar")
    mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    s.text(mx, my - 5 if above else my + 12, label, size=7.4, fill="#6d28d9", anchor="middle")


# ① 看板与提问
oval(410, 194, "查看经营看板\n7 / 30 / 90 天 · KPI 与趋势")
oval(410, 268, "自然语言问数\n指标 / 时间 / 平台 / 店铺", w=214)
oval(410, 340, "连续追问（继承筛选）", w=196)
oval(410, 408, "查看指标口径与定义", w=190, tone="slate")

# ② 答案与证据
oval(779, 194, "获得结构化答案\n简答 + 图表 + 明细", w=214)
oval(779, 268, "展开证据链", w=180, tone="green")
oval(779, 340, "下钻明细与导出", w=190, tone="green")
oval(779, 408, "澄清口径（多解时）", w=190, tone="amber")

# ③ 会话与留痕
oval(1165, 194, "会话恢复 / 新建 / 删除", w=214)
oval(1165, 268, "查看历史轮次与记忆范围", w=230)
oval(1165, 340, "对回答反馈（准确 / 有问题）", w=236)
oval(1165, 408, "查询审计记录（只读）", w=200, tone="slate")

# ④ 异常与边界
oval(410, 512, "写人类请求被拒绝", w=198, tone="red")
oval(410, 584, "越权店铺 / 跨组织被拒绝", w=216, tone="red")
oval(410, 656, "无数据 / 多币种 / 服务不可用\n分别报告", w=250, tone="amber")
oval(410, 724, "流式中断与重试", w=184, tone="slate")

# ⑤ P2
oval(779, 512, "训练 SQL 分支（P2）\n默认关闭", w=212, tone="purple")
oval(779, 590, "候选 SQL 只读校验与执行", w=234, tone="purple")
oval(779, 664, "与指标快照交叉核对", w=206, tone="purple")
oval(779, 728, "SQL 校验记录查看", w=190, tone="purple")

# ⑥ 指标管理（配置侧）
oval(1165, 508, "新建指标与必填校验", w=226, tone="teal")
oval(1165, 578, "口径版本：新建 / 发布 / 停用", w=262, tone="teal")
oval(1165, 648, "维护别名（冲突检测）", w=228, tone="teal")
oval(1165, 720, "启停用与删除保护", w=216, tone="teal")

# ⑦ 绑定 · 同步 · 模拟
oval(342, 826, "创建绑定\nREST / MCP / SIMULATION", w=216, tone="teal")
oval(592, 826, "绑定测试与启用切换", w=216, tone="teal")
oval(842, 826, "发布模拟接口与样例值", w=216, tone="teal")
oval(342, 918, "手动同步 / 定时调度", w=216, tone="teal")
oval(592, 918, "同步失败处置与重试", w=216, tone="teal")
oval(842, 918, "清除模拟数据", w=190, tone="teal")

# ⑧ 指标资产（只读）
oval(1165, 828, "指标列表 / 检索 / 可问清单", w=268, tone="green")
oval(1165, 912, "按授权范围取数\norg_id + 店铺集合", w=250, tone="slate")

# 关系
dashed_arrow(436, 292, 438, 318, "«extend»")          # 追问 extend 问数
dashed_arrow(660, 214, 672, 246, "«include»")          # 答案 include 证据链
s.line(504, 336, 682, 292, stroke="#7c3aed", sw=1.0, dash="5 3", marker="ar")
s.text(548, 312, "«include» 解析继承", size=7.2, fill="#6d28d9")
s.line(506, 402, 682, 404, stroke="#7c3aed", sw=1.0, dash="5 3", marker="ar")
s.text(560, 396, "«include» 口径命中", size=7.2, fill="#6d28d9")
dashed_arrow(777, 568, 777, 538, "«include»")
# 配置侧：发布口径 include 绑定成功取数（走组间空隙的折线，避免穿越其他用例）
s.line(1296, 601, 1296, 768, stroke="#7c3aed", sw=1.0, dash="5 3")
s.line(1296, 768, 592, 768, stroke="#7c3aed", sw=1.0, dash="5 3")
s.line(592, 768, 592, 800, stroke="#7c3aed", sw=1.0, dash="5 3", marker="ar")
s.text(640, 762, "«include» 至少一次成功取数 / 模拟返回（发布门槛）", size=7.4, fill="#6d28d9")
# 创建绑定 → 绑定测试
s.line(450, 826, 482, 826, stroke="#7c3aed", sw=1.0, dash="5 3", marker="ar")
s.text(466, 818, "«include»", size=7.0, fill="#6d28d9")
# 同步失败处置 «extend» 手动/定时同步
s.line(450, 908, 482, 908, stroke="#7c3aed", sw=1.0, dash="5 3", marker="ar")
s.text(466, 900, "«extend»", size=7.0, fill="#6d28d9")
# 手动同步与定时调度互为一体（同组说明）
s.text(342, 952, "手动与定时同一执行路径", size=7.0, fill="#0d9488", anchor="middle")

# 角色（左侧：配置侧与运行侧的使用者）
s.actor(96, 250, "运营分析人员", "提问、追问、看数")
s.actor(96, 640, "仓储 / 商品运营", "库存与低库存")
s.actor(96, 880, "指标与知识管理员", "指标 / 口径 / 绑定 / 模拟")
s.actor(1500, 300, "管理者", "看结论与趋势")
s.actor(1500, 640, "数据运营（同步值守）", "同步、重试、失败处置")
s.actor(1500, 880, "系统管理员 / 审计", "留痕复核、组织")

role_lines = [
    ((130, 250), (216, 250)), ((130, 640), (216, 700)), ((130, 880), (216, 860)),
    ((1466, 300), (1376, 250)), ((1466, 640), (1376, 700)), ((1466, 880), (1376, 860)),
]
for (x1, y1), (x2, y2) in role_lines:
    s.line(x1, y1, x2, y2, stroke="#cbd5e1", sw=0.9)
s.text(1400, 1040, "角色与用例对应见 §5.1", size=7.4, fill="#94a3b8", anchor="end")

# 外部依赖框
s.rect(216, 992, 720, 44, fill="#f8fafc", stroke="#cbd5e1", sw=1, rx=7, dash="5 4")
s.text(232, 1012, "外部依赖（不属本模块实现）：平台连接授权（数据接入中台）· 组织/角色/店铺范围（权限中台）· 库存事实（库存域）· 训练资料索引（知识域）",
       size=8.2, fill="#475569")
s.text(232, 1028, "指标定义、口径版本、绑定与同步、模拟应用均由本模块配置侧承担（FR-QA-42~51），对事实数据仍只读。", size=8.0, fill="#94a3b8")

s.legend(24, 1052, [("line", "#7c3aed", "«include» / «extend»"), ("line", "#cbd5e1", "参与者参与的用例"),
                    ("box", "#eff6ff", "运行侧用例"), ("box", "#e6fffb", "配置侧用例（可写）"),
                    ("box", "#ecfdf5", "只读展示 / 证据")], size=8.4)

out = os.path.join(os.path.dirname(__file__), "..", "usecase-qa.svg")
s.save(out)
print(export(out, dpi=160))

write_mmd(os.path.join(os.path.dirname(__file__), "..", "usecase-qa.mmd"), """
%% 图 usecase-qa 智能问数用例图（Mermaid 源码；成图见 usecase-qa.svg / .png）
flowchart LR
    A1((运营分析人员)) --> U1["查看经营看板 7/30/90"]
    A1 --> U2["自然语言问数"]
    A1 --> U3["连续追问（继承筛选）"]
    A1 --> U5["获得结构化答案"]
    A2((仓储 / 商品运营)) --> U6["查询 SKU 库存与低库存"]
    A2 --> U7["下钻明细与导出"]
    A3((指标与知识管理员)) --> U4["查看指标口径与定义"]
    A3 --> U8["澄清口径（多解时）"]
    A3 --> C1["新建指标与必填校验"]
    A3 --> C2["口径版本：新建 / 发布 / 停用"]
    A3 --> C3["维护别名（冲突检测）"]
    A3 --> C4["启停用与删除保护"]
    A3 --> C5["创建绑定 REST / MCP / SIMULATION"]
    A3 --> C7["发布模拟接口与样例值"]
    D1((数据运营（同步值守）)) --> C6["手动同步 / 定时调度"]
    D1 --> C8["同步失败处置与重试"]
    M1((管理者)) --> U1
    M1 --> U5
    S1((系统管理员 / 审计)) --> U10["会话恢复 / 新建 / 删除"]
    S1 --> U11["查询审计记录（只读）"]
    S1 --> C9["指标列表 / 检索 / 可问清单"]

    U3 -.->|«extend»| U2
    U2 -.->|«include»| U12["解析指标 / 时间 / 平台 / 店铺"]
    U5 -.->|«include»| U13["证据链：口径 / 来源 / data_as_of / 质量"]
    U5 -.->|«include»| U14["图表与可下钻明细"]
    U8 -.->|«extend»| U2
    U15["训练 SQL 分支（P2）"] -.->|«extend»| U2
    U15 -.->|«include»| U16["单条只读 SQL 校验"]
    C2 -.->|«include» 发布门槛| C5
    C5 -.->|«include»| C51["绑定测试"]
    C6 -.->|«extend»| C61["定时同步"]
    U17["写人类请求"] -.->|被拒绝| U18["WRITE_REJECTED"]
    U19["越权店铺 / 跨组织"] -.->|被拒绝| U20["PERMISSION_DENIED"]

    subgraph CFG["配置侧（本模块，可写）"]
      C1; C2; C3; C4; C5; C6; C7; C8; C9
    end
    subgraph EXT["外部依赖（不属本模块实现）"]
      E1["平台连接与授权"]
      E2["组织 / 角色 / 店铺范围"]
      E3["库存事实"]
      E4["训练资料索引"]
    end
""")
