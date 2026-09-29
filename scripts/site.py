#!/usr/bin/env python3
"""Builds the docs site: docs/**/*.md and README.md become site/, one page per document.

    python3 scripts/site.py            # writes site/ (gitignored)
    SITE_BASE=/ python3 scripts/site.py   # for a root-hosted copy; GitHub Pages serves /Brazier/

Needs the `markdown` package (pip install markdown). Everything else is the standard library.
Front matter is stripped; the first `# ` heading is the page title. Relative links to .md files become
page links, relative images and SVGs point at their copied files. The stylesheet is inline, on the brand:
ink ground, Archivo and Martian Mono (shipped as the app's own variable fonts), hairlines, radius 0.
"""
import html
import os
import re
import shutil
import sys
from pathlib import Path

try:
    import markdown
except ImportError:
    sys.exit("pip install markdown")

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
OUT = ROOT / "site"
BASE = os.environ.get("SITE_BASE", "/Brazier/")
if not BASE.endswith("/"):
    BASE += "/"
REPO = "https://github.com/Guys-Inc-Public/Brazier"
TAGLINE = "Alerts and dashboards for self-hosted Grafana"

# Sections in nav order: (title, docs subdirectory or single file).
SECTIONS = [
    ("Brief", "brief"),
    ("Concepts", "concepts"),
    ("Decisions", "decisions"),
    ("Reference", "reference"),
    ("Sessions", "sessions"),
    ("Privacy", "privacy.md"),
    ("Support", "support.md"),
]

FRONT = re.compile(r"\A---\n.*?\n---\n", re.S)
LINK = re.compile(r"""(\]\(|src="|href=")([^)"\s#]+)(#[^)"\s]*)?([)"])""")


class Page:
    def __init__(self, source: Path, rel: str):
        self.source = source          # the .md file
        self.rel = rel                # site path, "" for home, else "decisions/0001-…" (no trailing slash)
        text = source.read_text(encoding="utf-8")
        self.body = FRONT.sub("", text, count=1)
        m = re.search(r"^# (.+)$", self.body, re.M)
        self.title = m.group(1).strip() if m else source.stem
        self.body = self.body.replace(m.group(0), "", 1) if m else self.body

    @property
    def url(self) -> str:
        return BASE if not self.rel else f"{BASE}{self.rel}/"

    @property
    def out(self) -> Path:
        return OUT / "index.html" if not self.rel else OUT / self.rel / "index.html"


def page_rel(md: Path) -> str:
    """docs/decisions/0004-x.md -> decisions/0004-x ; README.md -> ''."""
    if md == ROOT / "README.md":
        return ""
    rel = md.relative_to(DOCS).with_suffix("")
    return rel.as_posix()


def collect() -> list[Page]:
    pages = [Page(ROOT / "README.md", "")]
    for md in sorted(DOCS.rglob("*.md")):
        pages.append(Page(md, page_rel(md)))
    return pages


def rewrite_links(page: Page, pages: dict[Path, Page]) -> str:
    """Resolve every relative link or src against the source file and point it at the site copy."""
    src_dir = page.source.parent

    def fix(m: re.Match) -> str:
        lead, target, frag, close = m.group(1), m.group(2), m.group(3) or "", m.group(4)
        if re.match(r"^[a-z]+:", target) or target.startswith("/") or target.startswith("{"):
            return m.group(0)
        try:
            resolved = (src_dir / target).resolve()
            rel = resolved.relative_to(ROOT).as_posix()
        except ValueError:
            return m.group(0)
        if resolved.suffix == ".md":
            if resolved in pages:
                return f"{lead}{pages[resolved].url}{frag}{close}"
            return f"{lead}{REPO}/blob/main/{rel}{frag}{close}"
        if rel.startswith("docs/diagrams/"):
            return f"{lead}{BASE}diagrams/{resolved.name}{close}"
        if rel.startswith("assets/"):
            return f"{lead}{BASE}{rel}{close}"
        return f"{lead}{REPO}/blob/main/{rel}{close}"

    return LINK.sub(fix, page.body)


def render_body(text: str) -> str:
    md = markdown.Markdown(extensions=["tables", "fenced_code", "toc"], extension_configs={"toc": {"toc_depth": "2-3"}})
    return md.convert(text)


def nav(pages: list[Page], current: Page) -> str:
    by_rel = {p.rel: p for p in pages}
    parts = ['<nav class="nav" aria-label="Documentation">']
    parts.append(f'<a class="navlink{" is-current" if current.rel == "" else ""}" href="{BASE}">Overview</a>')
    for title, where in SECTIONS:
        if where.endswith(".md"):
            p = by_rel.get(where[:-3])
            if p:
                cls = " is-current" if p is current else ""
                parts.append(f'<a class="navlink{cls}" href="{p.url}">{html.escape(title)}</a>')
            continue
        members = [p for p in pages if p.rel.startswith(where + "/")]
        if not members:
            continue
        parts.append(f'<div class="eyebrow">{html.escape(title)}</div>')
        for p in members:
            cls = " is-current" if p is current else ""
            parts.append(f'<a class="navlink sub{cls}" href="{p.url}">{html.escape(p.title)}</a>')
    parts.append("</nav>")
    return "\n".join(parts)


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{title} · Brazier</title>
<meta name="description" content="{description}">
<meta name="theme-color" content="#0e090f">
<link rel="icon" href="{base}assets/brand/icon/brazier-icon-tonal.ico" sizes="any">
<link rel="icon" type="image/svg+xml" href="{base}assets/brand/icon/brazier-icon-small-tonal.svg">
<link rel="apple-touch-icon" href="{base}assets/brand/icon/brazier-icon-tonal-on-ink-1024.png">
<style>
@font-face {{ font-family: "Archivo"; src: url("{base}fonts/Archivo[wdth,wght].ttf") format("truetype"); font-weight: 100 900; font-stretch: 62% 125%; font-display: swap; }}
@font-face {{ font-family: "Martian Mono"; src: url("{base}fonts/MartianMono[wdth,wght].ttf") format("truetype"); font-weight: 100 800; font-stretch: 75% 112.5%; font-display: swap; }}
:root {{
  --ink:#0e090f; --surface:#19121a; --raise:#231d25; --line:#322b34; --hot:#ff67bd; --lilac:#a984fb;
  --paper:#f6f4f7; --muted:#969098; --ok:#22dcb3; --wait:#fea845; --stop:#f43a57;
  --font:"Archivo", sans-serif; --mono:"Martian Mono", monospace;
  --s1:4px; --s2:8px; --s3:12px; --s4:20px; --s5:32px; --s6:52px; --s7:88px;
}}
* {{ box-sizing: border-box; }}
html {{ background: var(--ink); -webkit-text-size-adjust: 100%; }}
body {{ margin: 0; background: var(--ink); color: var(--paper); font-family: var(--font); font-size: 16px; line-height: 1.55; font-weight: 400;
  padding-left: env(safe-area-inset-left); padding-right: env(safe-area-inset-right); }}
a {{ color: var(--hot); text-decoration: none; }}
a:hover {{ text-decoration: underline; text-underline-offset: 3px; }}
.top {{ display: flex; align-items: center; gap: var(--s3); padding: var(--s3) var(--s4); border-bottom: 1px solid var(--line); background: var(--ink); min-height: 56px; }}
.top .mark {{ width: 28px; height: 28px; display: block; }}
.top .word {{ font-weight: 900; letter-spacing: -0.04em; font-size: 18px; color: var(--paper); }}
.top .tag {{ font-family: var(--mono); font-size: 12px; color: var(--muted); margin-left: var(--s2); }}
.top .repo {{ margin-left: auto; font-family: var(--mono); font-size: 12px; text-transform: uppercase; letter-spacing: 0.16em; color: var(--muted); }}
.top .repo:hover {{ color: var(--hot); text-decoration: none; }}
.frame {{ display: grid; grid-template-columns: 260px minmax(0, 1fr); min-height: calc(100dvh - 57px); }}
.nav {{ border-right: 1px solid var(--line); padding: var(--s4) var(--s3) var(--s6); position: sticky; top: 0; align-self: start; max-height: 100dvh; overflow: auto; }}
.eyebrow {{ font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.16em; color: var(--muted); margin: var(--s4) var(--s2) var(--s1); }}
.navlink {{ display: block; color: var(--paper); font-size: 14px; font-weight: 600; padding: 7px var(--s2); min-height: 32px; border-left: 2px solid transparent; }}
.navlink.sub {{ font-weight: 400; color: var(--muted); }}
.navlink:hover {{ background: var(--raise); text-decoration: none; color: var(--paper); }}
.navlink.is-current {{ color: var(--hot); border-left-color: var(--hot); }}
main {{ padding: var(--s5) var(--s4) var(--s7); max-width: calc(72ch + 2 * var(--s4)); }}
.crumb {{ font-family: var(--mono); font-size: 12px; text-transform: uppercase; letter-spacing: 0.16em; color: var(--muted); margin-bottom: var(--s3); }}
h1 {{ font-size: 34px; font-weight: 800; letter-spacing: -0.04em; line-height: 1.05; margin: 0 0 var(--s4); }}
h2 {{ font-size: 26px; font-weight: 800; letter-spacing: -0.04em; line-height: 1.1; margin: var(--s6) 0 var(--s3); padding-top: var(--s4); border-top: 1px solid var(--line); }}
h3 {{ font-size: 20px; font-weight: 700; letter-spacing: -0.02em; margin: var(--s5) 0 var(--s2); }}
h4 {{ font-size: 16px; font-weight: 700; margin: var(--s4) 0 var(--s2); }}
p, ul, ol {{ margin: 0 0 var(--s3); }}
li {{ margin-bottom: var(--s1); }}
strong {{ font-weight: 700; }}
em {{ color: var(--muted); font-style: italic; }}
hr {{ border: 0; border-top: 1px solid var(--line); margin: var(--s5) 0; }}
code, kbd {{ font-family: var(--mono); font-size: 0.86em; background: var(--surface); padding: 1px 5px; color: var(--paper); }}
pre {{ font-family: var(--mono); font-size: 13px; line-height: 1.5; background: var(--surface); border: 1px solid var(--line); padding: var(--s3) var(--s4); overflow-x: auto; margin: 0 0 var(--s4); }}
pre code {{ background: none; padding: 0; font-size: inherit; }}
blockquote {{ margin: 0 0 var(--s4); padding: var(--s2) var(--s4); border-left: 2px solid var(--line); color: var(--muted); }}
table {{ border-collapse: collapse; width: 100%; margin: 0 0 var(--s4); font-size: 14px; display: block; overflow-x: auto; }}
th, td {{ text-align: left; vertical-align: top; padding: var(--s2) var(--s3); border-top: 1px solid var(--line); }}
th {{ font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.16em; color: var(--muted); font-weight: 500; background: var(--surface); border-top: 0; }}
tr:last-child td {{ border-bottom: 1px solid var(--line); }}
img {{ max-width: 100%; height: auto; display: block; }}
.toc {{ display: none; }}
footer {{ border-top: 1px solid var(--line); padding: var(--s4); font-family: var(--mono); font-size: 12px; color: var(--muted); line-height: 1.7; }}
footer p {{ margin: 0 0 var(--s2); }}
footer a {{ color: var(--muted); text-decoration: underline; text-underline-offset: 3px; }}
footer a:hover {{ color: var(--hot); }}
@media (max-width: 860px) {{
  .frame {{ grid-template-columns: 1fr; }}
  .nav {{ position: static; max-height: none; border-right: 0; border-bottom: 1px solid var(--line); padding: var(--s3) var(--s2) var(--s4); }}
  .top {{ flex-wrap: wrap; padding: var(--s3) 16px; }}
  .top .tag {{ display: none; }}
  main {{ padding: var(--s4) 16px var(--s6); }}
  h1 {{ font-size: 28px; }}
  h2 {{ font-size: 22px; }}
}}
</style>
</head>
<body>
<header class="top">
  <a href="{base}" aria-label="Brazier home" style="display:flex;align-items:center;gap:12px;color:inherit">
    <img class="mark" src="{base}assets/brand/mark/brazier-mark-tonal.svg" alt="" width="28" height="28">
    <span class="word">BRAZIER</span>
  </a>
  <span class="tag">{tagline}</span>
  <a class="repo" href="{repo}">GitHub</a>
</header>
<div class="frame">
{nav}
<main>
  <div class="crumb">{crumb}</div>
  <h1>{title}</h1>
{body}
</main>
</div>
<footer>
  <p>Brazier is not affiliated with or endorsed by Grafana Labs. Grafana is a trademark of Grafana Labs.</p>
  <p>Source and licence (MIT): <a href="{repo}">{repo_short}</a>. Fonts Archivo and Martian Mono, SIL Open Font License 1.1.</p>
  <p>© Guys Inc · <a href="{base}privacy/">Privacy</a> · <a href="{base}support/">Support</a></p>
</footer>
</body>
</html>
"""


def crumb_for(page: Page) -> str:
    if not page.rel:
        return "Overview"
    head = page.rel.split("/")[0]
    if head in ("privacy", "support"):
        return "Reference"
    for title, where in SECTIONS:
        if where == head:
            return title
    return head


def description_for(page: Page) -> str:
    for line in page.body.splitlines():
        s = line.strip()
        if s and not s.startswith(("#", "!", "|", "<", "```", "_", "-", "*")):
            return html.escape(re.sub(r"[*_`\[\]]", "", s)[:160])
    return TAGLINE


def build() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir()
    pages = collect()
    by_source = {p.source.resolve(): p for p in pages}
    for page in pages:
        text = rewrite_links(page, by_source)
        body = render_body(text)
        page.out.parent.mkdir(parents=True, exist_ok=True)
        page.out.write_text(TEMPLATE.format(
            title=html.escape(page.title), description=description_for(page), base=BASE, tagline=TAGLINE,
            repo=REPO, repo_short="Guys-Inc-Public/Brazier", nav=nav(pages, page), crumb=html.escape(crumb_for(page)), body=body,
        ), encoding="utf-8")
    (OUT / "diagrams").mkdir()
    for svg in (DOCS / "diagrams").glob("*.svg"):
        shutil.copy(svg, OUT / "diagrams" / svg.name)
    shutil.copytree(ROOT / "assets", OUT / "assets")
    fonts = OUT / "fonts"
    fonts.mkdir()
    for f in (ROOT / "app" / "Brazier" / "Resources" / "Fonts").iterdir():
        shutil.copy(f, fonts / f.name)
    (OUT / ".nojekyll").write_text("")
    print(f"{len(pages)} pages -> {OUT.relative_to(ROOT)}/ (base {BASE})")


if __name__ == "__main__":
    build()
