# -*- coding: utf-8 -*-
"""
生成 SRS 图表的轻量 SVG 绘图库。

为什么不用 Mermaid / PlantUML：
  本环境无 Chromium（mermaid-cli 依赖）、无 graphviz / Java，且 /usr/share/fonts 中
  不存在 CJK 字体，仅 PyMuPDF 内置的 Droid Sans Fallback 可正确渲染中文。
  因此本目录所有图均以「.mmd 源码（评审可读、可作为详细设计输入） + 程序化生成的
  .svg/.png」成对保存：SVG 由本脚本绘制，PNG 由 PyMuPDF 将 SVG 转 PDF 后栅格化，
  保证中文、线条、箭头均正确落地。
"""
import math
import os

FONT = "Droid Sans Fallback, Noto Sans CJK SC, Microsoft YaHei, sans-serif"
MONO = "DejaVu Sans Mono, Menlo, monospace"

# 统一配色（与高保真原型保持同一套语义色）
C = dict(
    ink="#0f172a", sub="#334155", muted="#64748b", faint="#94a3b8",
    line="#cbd5e1", grid="#eef2f8", bg="#ffffff", panel="#f8fafc",
    blue="#2563eb", blue_bg="#eff6ff", blue_ln="#bfdbfe",
    cyan="#0891b2", cyan_bg="#ecfeff", green="#059669", green_bg="#ecfdf5",
    amber="#b45309", amber_bg="#fffbeb", amber_ln="#fcd34d",
    red="#b91c1c", red_bg="#fef2f2", red_ln="#fca5a5",
    purple="#6d28d9", purple_bg="#f5f3ff", purple_ln="#c4b5fd",
    slate_bg="#f1f5f9",
)


def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;")
            .replace(">", "&gt;").replace('"', "&quot;"))


def _text_w(s):
    """按全角/半角估算文本宽度（用于居中与换行）。"""
    w = 0
    for ch in s:
        w += 1.0 if ord(ch) > 0x2E80 else 0.55
    return w


class SVG:
    def __init__(self, w, h, title=None, subtitle=None, bg=C["bg"], pad=24):
        self.w, self.h = w, h
        self.parts = []
        self.title = title
        self.subtitle = subtitle
        self.bg = bg
        self.pad = pad
        self.off_y = 0
        if title:
            self.off_y = 54 if subtitle else 38

    # ---------- 基础图元 ----------
    def raw(self, s):
        self.parts.append(s)

    def rect(self, x, y, w, h, fill="none", stroke="none", sw=1.2, rx=0,
             dash=None, opacity=None, extra=""):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        o = f' fill-opacity="{opacity}"' if opacity is not None else ""
        self.parts.append(
            f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx}" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}{o} {extra}/>')

    def circle(self, cx, cy, r, fill="none", stroke="none", sw=1.2, opacity=None):
        o = f' fill-opacity="{opacity}"' if opacity is not None else ""
        self.parts.append(
            f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="{fill}" '
            f'stroke="{stroke}" stroke-width="{sw}"{o}/>')

    def ellipse(self, cx, cy, rx, ry, fill="none", stroke="none", sw=1.2):
        self.parts.append(
            f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')

    def line(self, x1, y1, x2, y2, stroke=C["line"], sw=1.2, dash=None,
             marker=None, opacity=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        m = f' marker-end="url(#{marker})"' if marker else ""
        o = f' stroke-opacity="{opacity}"' if opacity is not None else ""
        self.parts.append(
            f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
            f'stroke="{stroke}" stroke-width="{sw}"{d}{m}{o}/>')

    def path(self, d, stroke="none", fill="none", sw=1.2, dash=None,
             marker=None, opacity=None, marker_start=None):
        ds = f' stroke-dasharray="{dash}"' if dash else ""
        m = f' marker-end="url(#{marker})"' if marker else ""
        ms = f' marker-start="url(#{marker_start})"' if marker_start else ""
        o = f' fill-opacity="{opacity}"' if opacity is not None else ""
        self.parts.append(
            f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"'
            f'{ds}{m}{ms}{o}/>')

    def poly(self, pts, fill="none", stroke="none", sw=1.2, marker=None):
        p = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        m = f' marker-end="url(#{marker})"' if marker else ""
        self.parts.append(
            f'<polygon points="{p}" fill="{fill}" stroke="{stroke}" '
            f'stroke-width="{sw}"{m}/>')

    # ---------- 文本 ----------
    def text(self, x, y, s, size=12, fill=C["ink"], anchor="start",
             weight="normal", family=FONT, opacity=None, ls=None):
        o = f' opacity="{opacity}"' if opacity is not None else ""
        l = f' letter-spacing="{ls}"' if ls else ""
        self.parts.append(
            f'<text x="{x:.1f}" y="{y:.1f}" font-family="{family}" font-size="{size}" '
            f'fill="{fill}" text-anchor="{anchor}" font-weight="{weight}"{o}{l}>{esc(s)}</text>')

    def para(self, x, y, s, width, size=11, fill=C["sub"], lh=1.55,
             anchor="start", weight="normal", family=FONT):
        """简易自动换行：按估算宽度断行，返回结束 y。"""
        max_chars = max(4, int(width / (size * 1.0)))
        lines, cur = [], ""
        for ch in s:
            if ch == "\n":
                lines.append(cur); cur = ""
                continue
            if _text_w(cur + ch) > max_chars:
                lines.append(cur)
                cur = ch
            else:
                cur += ch
        if cur:
            lines.append(cur)
        yy = y
        for ln in lines:
            self.text(x, yy, ln, size=size, fill=fill, anchor=anchor, weight=weight, family=family)
            yy += size * lh
        return yy

    def badge(self, x, y, s, tone="slate", size=10, padx=7, h=18, mono=False):
        """小号标签，返回右边界 x。"""
        palette = dict(
            slate=(C["slate_bg"], "#475569"), blue=(C["blue_bg"], "#1d4ed8"),
            green=(C["green_bg"], "#047857"), amber=(C["amber_bg"], "#b45309"),
            red=(C["red_bg"], "#b91c1c"), purple=(C["purple_bg"], "#6d28d9"),
            cyan=(C["cyan_bg"], "#0e7490"),
        )
        bg, fg = palette.get(tone, palette["slate"])
        w = _text_w(s) * size * 1.0 + padx * 2
        self.rect(x, y - h / 2, w, h, fill=bg, rx=h / 2)
        self.text(x + padx, y + size * 0.36, s, size=size, fill=fg,
                  family=MONO if mono else FONT, weight="bold")
        return x + w

    def chip(self, x, y, s, tone="soft", size=10, h=18):
        pal = dict(soft=("#f1f5f9", "#475569", "#e2e8f0"),
                   blue=("#eff6ff", "#1d4ed8", "#bfdbfe"),
                   green=("#ecfdf5", "#047857", "#a7f3d0"),
                   amber=("#fffbeb", "#b45309", "#fde68a"),
                   red=("#fef2f2", "#b91c1c", "#fecaca"),
                   purple=("#f5f3ff", "#6d28d9", "#ddd6fe"))
        bg, fg, bd = pal.get(tone, pal["soft"])
        w = _text_w(s) * size * 1.0 + 12
        self.rect(x, y - h / 2, w, h, fill=bg, stroke=bd, sw=0.8, rx=4)
        self.text(x + 6, y + size * 0.36, s, size=size, fill=fg)
        return x + w

    # ---------- 复合图元 ----------
    def node(self, x, y, w, h, title, sub=None, tone="blue", tag=None,
             size=12, sub_size=9.5, rx=8, dash=None, solid_title=True):
        """圆角矩形节点：标题 + 可选副标题 + 可选右上角小标签。"""
        pal = dict(
            blue=(C["blue_bg"], C["blue"], "#1e3a8a", "#1d4ed8"),
            green=(C["green_bg"], "#10b981", "#065f46", "#047857"),
            amber=(C["amber_bg"], "#f59e0b", "#92400e", "#b45309"),
            red=(C["red_bg"], "#ef4444", "#991b1b", "#b91c1c"),
            purple=(C["purple_bg"], C["purple"], "#4c1d95", "#6d28d9"),
            cyan=(C["cyan_bg"], C["cyan"], "#155e75", "#0e7490"),
            slate=(C["panel"], "#94a3b8", "#1e293b", "#475569"),
        )
        bg, bd, tcol, scol = pal.get(tone, pal["slate"])
        self.rect(x, y, w, h, fill=bg, stroke=bd, sw=1.25, rx=rx, dash=dash)
        if sub:
            ty = y + h / 2 - 4
            self.text(x + w / 2, ty, title, size=size, fill=tcol, anchor="middle",
                      weight="bold" if solid_title else "normal")
            self.text(x + w / 2, ty + sub_size + 7, sub, size=sub_size,
                      fill=scol, anchor="middle")
        else:
            self.text(x + w / 2, y + h / 2 + size * 0.36, title, size=size,
                      fill=tcol, anchor="middle",
                      weight="bold" if solid_title else "normal")
        if tag:
            tw = _text_w(tag) * 8.6 + 10
            self.rect(x + w - tw - 5, y + 5, tw, 14, fill="#ffffff", stroke=bd,
                      sw=0.7, rx=7, opacity=None)
            self.text(x + w - tw / 2 - 5, y + 15, tag, size=8.6, fill=scol,
                      anchor="middle", weight="bold")
        return (x, y, w, h)

    def cylinder(self, cx, cy, w, h, label, sub=None, tone="green"):
        pal = dict(green=(C["green_bg"], "#10b981", "#065f46"),
                   blue=(C["blue_bg"], C["blue"], "#1e3a8a"),
                   slate=(C["panel"], "#94a3b8", "#1e293b"),
                   purple=(C["purple_bg"], C["purple"], "#4c1d95"))
        bg, bd, tc = pal.get(tone, pal["slate"])
        x, y = cx - w / 2, cy - h / 2
        ry = 8
        self.path(f"M{x},{y+ry} A{w/2},{ry} 0 0 1 {x+w},{y+ry} L{x+w},{y+h-ry} "
                  f"A{w/2},{ry} 0 0 1 {x},{y+h-ry} Z", fill=bg, stroke=bd, sw=1.2)
        self.path(f"M{x},{y+ry} A{w/2},{ry} 0 0 0 {x+w},{y+ry}", stroke=bd, sw=1.2)
        self.text(cx, cy + 2, label, size=11.5, fill=tc, anchor="middle", weight="bold")
        if sub:
            self.text(cx, cy + 15, sub, size=9, fill="#475569", anchor="middle")

    def actor(self, cx, cy, label, sub=None):
        """UML 简笔小人。"""
        self.circle(cx, cy - 22, 7, fill="#ffffff", stroke=C["sub"], sw=1.3)
        self.line(cx, cy - 15, cx, cy + 4, stroke=C["sub"], sw=1.3)
        self.line(cx - 11, cy - 7, cx + 11, cy - 7, stroke=C["sub"], sw=1.3)
        self.line(cx, cy + 4, cx - 9, cy + 19, stroke=C["sub"], sw=1.3)
        self.line(cx, cy + 4, cx + 9, cy + 19, stroke=C["sub"], sw=1.3)
        self.text(cx, cy + 34, label, size=11, fill=C["ink"], anchor="middle", weight="bold")
        if sub:
            self.text(cx, cy + 47, sub, size=9, fill=C["muted"], anchor="middle")

    def box4(self, x, y, w, h, label, tone="blue", rx=0):
        """纯色横条（泳道标题等）。"""
        pal = dict(blue=("#1d4ed8", "#ffffff"), slate=("#e2e8f0", "#334155"),
                   green=("#047857", "#ffffff"), purple=("#6d28d9", "#ffffff"),
                   amber=("#b45309", "#ffffff"), dark=("#0f172a", "#ffffff"))
        fill, fg = pal.get(tone, pal["blue"])
        self.rect(x, y, w, h, fill=fill, rx=rx)
        self.text(x + w / 2, y + h / 2 + 4, label, size=11, fill=fg,
                  anchor="middle", weight="bold")

    def legend(self, x, y, items, size=10, gap=18):
        """items: [(kind, color, label)]；kind ∈ dot/line/dash/box。"""
        cx = x
        for kind, color, label in items:
            if kind == "dot":
                self.circle(cx + 5, y, 4.5, fill=color)
                cx += 14
            elif kind == "line":
                self.line(cx, y, cx + 18, y, stroke=color, sw=1.6)
                cx += 22
            elif kind == "dash":
                self.line(cx, y, cx + 18, y, stroke=color, sw=1.6, dash="4 3")
                cx += 22
            elif kind == "box":
                self.rect(cx, y - 6, 12, 12, fill=color, rx=2)
                cx += 16
            self.text(cx, y + 4, label, size=size, fill=C["sub"])
            cx += _text_w(label) * size + gap
        return cx

    # ---------- 导出 ----------
    def render(self):
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
                f'viewBox="0 0 {self.w} {self.h}">'
                f'<defs>'
                f'<marker id="ar" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto">'
                f'<path d="M0,0 L10,4 L0,8 z" fill="#334155"/></marker>'
                f'<marker id="ar-b" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto">'
                f'<path d="M0,0 L10,4 L0,8 z" fill="{C["blue"]}"/></marker>'
                f'<marker id="ar-r" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto">'
                f'<path d="M0,0 L10,4 L0,8 z" fill="#dc2626"/></marker>'
                f'<marker id="ar-g" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto">'
                f'<path d="M0,0 L10,4 L0,8 z" fill="#059669"/></marker>'
                f'<marker id="ar-a" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto">'
                f'<path d="M0,0 L10,4 L0,8 z" fill="#d97706"/></marker>'
                f'</defs>'
                f'<rect width="{self.w}" height="{self.h}" fill="{self.bg}"/>')
        body = "".join(self.parts)
        head = head.replace('</defs>', '</defs>')
        # 标题区在最上层绘制，避免被泳道底纹遮挡
        hdr = ""
        if self.title:
            hdr += (f'<rect x="0" y="0" width="{self.w}" height="{self.off_y}" fill="#f8fafc"/>'
                    f'<rect x="0" y="{self.off_y-1}" width="{self.w}" height="1" fill="#e2e8f0"/>'
                    f'<text x="24" y="25" font-family="{FONT}" font-size="15" '
                    f'font-weight="bold" fill="#0f172a">{esc(self.title)}</text>')
            if self.subtitle:
                hdr += (f'<text x="24" y="44" font-family="{FONT}" font-size="10.5" '
                        f'fill="#64748b">{esc(self.subtitle)}</text>')
        return head + hdr + body + "</svg>"

    def save(self, path):
        svg_path = path if path.endswith(".svg") else path + ".svg"
        os.makedirs(os.path.dirname(svg_path), exist_ok=True)
        with open(svg_path, "w", encoding="utf-8") as f:
            f.write(self.render())
        return svg_path


def export(svg_path, png_path=None, dpi=170):
    """用 PyMuPDF 将 SVG 转 PDF 再栅格化为 PNG（无需浏览器）。"""
    import pymupdf
    d = pymupdf.open(svg_path)
    pdf_bytes = d.convert_to_pdf()
    doc = pymupdf.open("pdf", pdf_bytes)
    page = doc[0]
    pix = page.get_pixmap(dpi=dpi, alpha=False)
    png_path = png_path or svg_path.replace(".svg", ".png")
    pix.save(png_path)
    return png_path, pix.width, pix.height


def write_mmd(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text.strip() + "\n")
    return path
