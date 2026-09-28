#!/usr/bin/env python3
"""Repository checks: front matter on every docs page, valid JSON in every board spec."""
import json, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
errors = []
FM = re.compile(r"\A---\n(.*?)\n---\n", re.S)
for md in sorted((ROOT / "docs").rglob("*.md")):
    rel = md.relative_to(ROOT)
    m = FM.match(md.read_text())
    if not m: errors.append(f"{rel}: missing front matter"); continue
    fm = m.group(1)
    keys = ("session", "repo", "branch", "driver", "outcome") if "sessions" in rel.parts else ("owner", "reviewed", "review")
    for k in keys:
        if not re.search(rf"^{k}:\s*\S", fm, re.M): errors.append(f"{rel}: front matter missing '{k}'")
for js in sorted((ROOT / "docs" / "diagrams").glob("*.board.json")):
    try: json.loads(js.read_text())
    except Exception as e: errors.append(f"{js.relative_to(ROOT)}: {e}")
for e in errors: print(e)
print("OK" if not errors else f"{len(errors)} problem(s)")
sys.exit(1 if errors else 0)
