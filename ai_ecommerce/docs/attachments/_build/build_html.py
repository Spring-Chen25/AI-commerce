#!/usr/bin/env python3
"""requirements-qa.md → requirements-qa.html（自包含单文件阅读版）

用法：python3 ai_ecommerce/docs/attachments/_build/build_html.py
输出：ai_ecommerce/docs/requirements-qa.html

特性：
- 全部 8 张图以 PNG data URI 内嵌，HTML 单文件分发，无外部依赖
- 自动识别 md 中的 `图 N ...` 图注，在对应段落插入内嵌图片
- 支持标题 / 表格 / 代码块 / 块引用 / 有序无序列表 / 行内代码 / 粗体
- 侧边目录（H2/H3）+ 阅读进度 + 打印样式
"""
import base64
import html
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(DOCS, "requirements-qa.md")
OUT = os.path.join(DOCS, "requirements-qa.html")
ATT = os.path.join(DOCS, "attachments")

FIGURES = [
    ("图 1", "flow-qa-main.png", "业务流程：主链路与异常分支"),
    ("图 2", "usecase-qa.png", "用例图：参与者与用例关系"),
    ("图 3", "flow-qa-states.png", "状态机：轮次状态 × 质量状态"),
    ("图 4", "sequence-qa-stream.png", "时序：流式回答"),
    ("图 5", "sequence-qa-session.png", "时序：看板加载与会话恢复"),
    ("图 6", "flow-qa-data.png", "数据流向：四类数据性质与失败处理"),
    ("图 7", "er-qa.png", "概念 ER 图"),
    ("图 8", "flow-qa-metric.png", "指标配置主链路"),
]


def data_uri(name):
    p = os.path.join(ATT, name)
    with open(p, "rb") as f:
        return "data:image/png;base64," + base64.b64encode(f.read()).decode()


def inline(s):
    """行内标记：先用占位符保护 `code`，再整体处理粗体/斜体，最后还原。"""
    codes = []

    def _stash(m):
        codes.append(m.group(1))
        return "\x00%d\x00" % (len(codes) - 1)

    work = re.sub(r"`([^`]+)`", _stash, s)
    work = html.escape(work)
    work = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", work)
    work = re.sub(r"(?<!\*)\*([^*]+?)\*(?!\*)", r"<em>\1</em>", work)

    def _restore(m):
        return "<code>%s</code>" % html.escape(codes[int(m.group(1))])

    return re.sub(r"\x00(\d+)\x00", _restore, work)


def slug(text, seen):
    s = re.sub(r"<[^>]+>", "", text)
    s = re.sub(r"[^\w\u4e00-\u9fff]+", "-", s).strip("-").lower()
    if not s:
        s = "sec"
    if s in seen:
        seen[s] += 1
        s = "%s-%d" % (s, seen[s])
    else:
        seen[s] = 1
    return s


def split_row(line):
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    cells, buf, esc, code = [], "", False, False
    for ch in line:
        if ch == "`" and not esc:
            code = not code
            buf += ch
            continue
        if ch == "\\" and not esc:
            esc = True
            continue
        if ch == "|" and not esc and not code:
            cells.append(buf.strip())
            buf = ""
            continue
        buf += ch
        esc = False
    cells.append(buf.strip())
    return cells


def build():
    md = open(SRC, encoding="utf-8").read()
    lines = md.split("\n")

    figs = {k: (data_uri(f), cap) for k, f, cap in FIGURES}
    used = set()

    out = []
    toc = []
    seen = {}
    i = 0
    n = len(lines)

    while i < n:
        ln = lines[i]
        s = ln.rstrip()

        # 代码块
        if s.startswith("```"):
            lang = s[3:].strip()
            i += 1
            block = []
            while i < n and not lines[i].strip().startswith("```"):
                block.append(lines[i])
                i += 1
            i += 1
            out.append(
                '<pre class="ascii"><code>%s</code></pre>' % html.escape("\n".join(block))
            )
            continue

        # 表格
        if s.startswith("|") and i + 1 < n and re.match(r"^\|[\s:|-]+\|?$", lines[i + 1].strip()):
            head = split_row(s)
            i += 2
            body = []
            while i < n and lines[i].strip().startswith("|"):
                body.append(split_row(lines[i]))
                i += 1
            out.append('<div class="tw"><table>')
            out.append("<thead><tr>" + "".join("<th>%s</th>" % inline(c) for c in head) + "</tr></thead>")
            out.append("<tbody>")
            for r in body:
                out.append("<tr>" + "".join("<td>%s</td>" % inline(c) for c in r) + "</tr>")
            out.append("</tbody></table></div>")
            continue

        # 标题
        m = re.match(r"^(#{1,6})\s+(.*)$", s)
        if m:
            lvl = len(m.group(1))
            text = m.group(2)
            hid = slug(text, seen)
            if lvl == 1:
                out.append("<h1>%s</h1>" % inline(text))
            else:
                out.append('<h%d id="%s">%s</h%d>' % (lvl, hid, inline(text), lvl))
                if lvl in (2, 3):
                    toc.append((lvl, hid, re.sub(r"<[^>]+>", "", inline(text))))
            i += 1
            continue

        # 块引用（可跨多行）
        if s.startswith(">"):
            block = []
            while i < n and lines[i].strip().startswith(">"):
                block.append(re.sub(r"^>\s?", "", lines[i].rstrip()))
                i += 1
            inner = "\n".join(x for x in block if x.strip())
            out.append('<blockquote>%s</blockquote>' % inline(inner).replace("\n", "<br/>"))
            continue

        # 分隔线
        if re.match(r"^-{3,}$", s.strip()):
            out.append("<hr/>")
            i += 1
            continue

        # 有序列表
        if re.match(r"^\d+\.\s+", s):
            items = []
            while i < n and re.match(r"^\d+\.\s+", lines[i]):
                txt = re.sub(r"^\d+\.\s+", "", lines[i].rstrip())
                # 续行缩进
                i += 1
                while i < n and lines[i].startswith("   ") and lines[i].strip():
                    txt += "<br/>" + lines[i].strip()
                    i += 1
                items.append(txt)
            out.append("<ol>" + "".join("<li>%s</li>" % inline(t) for t in items) + "</ol>")
            continue

        # 无序列表
        if re.match(r"^[-*]\s+", s):
            items = []
            while i < n and re.match(r"^[-*]\s+", lines[i]):
                txt = re.sub(r"^[-*]\s+", "", lines[i].rstrip())
                i += 1
                while i < n and lines[i].startswith("  ") and lines[i].strip():
                    txt += "<br/>" + lines[i].strip()
                    i += 1
                items.append(txt)
            out.append("<ul>" + "".join("<li>%s</li>" % inline(t) for t in items) + "</ul>")
            continue

        # 空行
        if not s.strip():
            i += 1
            continue

        # 普通段落（合并到下一个空行）
        para = [s]
        i += 1
        while i < n and lines[i].strip() and not re.match(
            r"^(#{1,6}\s|\||>|```|-{3,}$|\d+\.\s|[-*]\s)", lines[i].strip()
        ):
            para.append(lines[i].strip())
            i += 1
        text = "\n".join(para)

        # Markdown 图片语法 → 内嵌 data URI
        im = re.match(r"^!\[(.*?)\]\((.*?)\)$", text.strip())
        if im:
            cap, path = im.group(1), im.group(2)
            fname = os.path.basename(path)
            if os.path.exists(os.path.join(ATT, fname)):
                out.append(
                    '<figure id="fig-%s"><img alt="%s" src="%s"/><figcaption>%s</figcaption></figure>'
                    % (fname.split(".")[0], html.escape(cap), data_uri(fname), inline(cap))
                )
                for k, f, _ in FIGURES:
                    if f == fname:
                        used.add(k)
                continue

        # 图注：独立一段以「图 N」开头 → 插入内嵌图片
        fm = re.match(r"^\*\*?(图\s*[1-8])", text)
        if fm:
            key = fm.group(1).replace(" ", " ")
            key = re.sub(r"\s+", " ", key)
            if key in figs and key not in used:
                uri, cap = figs[key]
                out.append(
                    '<figure id="fig-%s"><img alt="%s" src="%s"/><figcaption>%s</figcaption></figure>'
                    % (key.replace(" ", ""), html.escape(cap), uri, inline(text))
                )
                used.add(key)
                continue

        out.append("<p>%s</p>" % inline(text).replace("\n", "<br/>"))

    # 未被正文引用的图，追加到 HTML 末尾（保证图不被漏掉）
    missing = [k for k, _, _ in FIGURES if k not in used]
    if missing:
        out.append('<h2 id="appendix-figs">附：图集</h2>')
        for k in missing:
            uri, cap = figs[k]
            out.append('<figure><img alt="%s" src="%s"/><figcaption>%s %s</figcaption></figure>'
                       % (html.escape(cap), uri, k, cap))

    nav = "".join(
        '<a class="lvl%d" href="#%s">%s</a>' % (lvl, hid, html.escape(txt))
        for lvl, hid, txt in toc
    )

    title = "智能问数 Agent（M3/QA）软件需求规格说明书 · V2.1"
    page = """<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>{TITLE}</title>
<style>
:root{--fg:#1a1f27;--muted:#5b6675;--line:#e2e7ee;--bg:#fff;--accent:#1f6feb;--soft:#f6f8fa;--warn:#fff8e6}
*{box-sizing:border-box}
body{margin:0;font:15px/1.75 -apple-system,"PingFang SC","Microsoft YaHei",sans-serif;color:var(--fg);background:var(--bg)}
#prog{position:fixed;top:0;left:0;height:3px;background:var(--accent);width:0;z-index:99}
.wrap{display:flex;max-width:1560px;margin:0 auto}
nav{position:sticky;top:0;height:100vh;overflow:auto;width:310px;flex:0 0 310px;
    border-right:1px solid var(--line);padding:18px 12px 40px;background:var(--soft);font-size:13px}
nav .nt{font-weight:700;margin:0 0 10px;font-size:14px}
nav a{display:block;padding:3px 8px;color:#3c4655;text-decoration:none;border-radius:5px;
      overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
nav a:hover{background:#e8eefb;color:var(--accent)}
nav a.lvl3{padding-left:20px;font-size:12.5px;color:var(--muted)}
nav a.lvl2{font-weight:600;margin-top:4px}
main{flex:1;min-width:0;padding:34px 52px 120px;max-width:1080px}
h1{font-size:26px;line-height:1.4;border-bottom:3px solid var(--accent);padding-bottom:12px;margin:0 0 6px}
h2{font-size:21px;margin:44px 0 14px;padding-bottom:8px;border-bottom:1px solid var(--line);scroll-margin-top:14px}
h3{font-size:17px;margin:30px 0 10px;color:#13305c;scroll-margin-top:14px}
h4{font-size:15.5px;margin:22px 0 8px;padding-left:10px;border-left:4px solid var(--accent);scroll-margin-top:14px}
h5,h6{font-size:14.5px;margin:18px 0 6px;color:var(--muted)}
p{margin:10px 0}
code{background:#eef1f6;padding:1px 5px;border-radius:4px;font-size:12.8px;
     font-family:"DejaVu Sans Mono",Consolas,monospace;color:#b3005a}
pre.ascii{background:var(--soft);border:1px solid var(--line);border-radius:8px;padding:14px 16px;
          overflow:auto;font-size:11.5px;line-height:1.45}
pre.ascii code{background:none;color:#22303f;padding:0;font-size:11.5px}
.tw{overflow:auto;margin:14px 0;border:1px solid var(--line);border-radius:8px}
table{border-collapse:collapse;width:100%;font-size:13px;min-width:520px}
th{background:#eef2f9;text-align:left;padding:9px 10px;font-weight:600;white-space:nowrap;
   border-bottom:2px solid #d5dded;position:sticky;top:0}
td{padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
tbody tr:nth-child(even){background:#fbfcfe}
tbody tr:hover{background:#f2f6ff}
blockquote{margin:14px 0;padding:12px 16px;background:var(--warn);border-left:4px solid #e3b341;
           border-radius:0 6px 6px 0;font-size:13.5px;color:#4a3a10}
figure{margin:20px 0;text-align:center}
figure img{max-width:100%;height:auto;border:1px solid var(--line);border-radius:8px;background:#fff}
figcaption{font-size:12.5px;color:var(--muted);margin-top:8px}
hr{border:none;border-top:1px solid var(--line);margin:34px 0}
ol,ul{padding-left:24px;margin:10px 0}
li{margin:5px 0}
a{color:var(--accent)}
@media (max-width:1000px){nav{display:none}main{padding:22px 18px 80px}}
@media print{nav,#prog{display:none}main{max-width:none;padding:0}
  h2,h3{page-break-after:avoid}table,figure{page-break-inside:avoid}}
</style></head><body>
<div id="prog"></div>
<div class="wrap">
<nav><p class="nt">目录</p>{NAV}</nav>
<main>{BODY}</main>
</div>
<script>
(function(){var p=document.getElementById('prog');
window.addEventListener('scroll',function(){
var h=document.documentElement;
var m=h.scrollHeight-h.clientHeight;
p.style.width=(m>0?(h.scrollTop/m*100):0)+'%';});})();
</script>
</body></html>"""

    page = page.replace("{TITLE}", html.escape(title)).replace("{NAV}", nav).replace("{BODY}", "\n".join(out))

    with open(OUT, "w", encoding="utf-8") as f:
        f.write(page)
    print("写出 %s  %.2f MB  图片内嵌 %d/8  TOC %d 项"
          % (OUT, len(page.encode()) / 1048576, len(used), len(toc)))


if __name__ == "__main__":
    build()
