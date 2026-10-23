#!/usr/bin/env python3
"""Check Google Play character limits for store/android/listing.md.

Each text block is a fenced ``` block right after a marker comment like
<!-- en.short -->. Play counts characters (Unicode code points), so Khmer
combining marks count as characters too.

    python3 store/android/compose/check_listing.py
"""
import pathlib, re, sys

LIMITS = {"name": 30, "name_alt": 30, "short": 80, "full": 4000}
md = (pathlib.Path(__file__).resolve().parents[1] / "listing.md").read_text("utf-8")
blocks = re.findall(r"<!-- (\w+)\.(\w+) -->\s*```\n(.*?)\n```", md, re.S)
bad = 0
for lang, key, text in blocks:
    n, lim = len(text), LIMITS[key]
    ok = n <= lim
    bad += not ok
    print(f"{lang}.{key:<9} {n:>5} / {lim:<5} {'ok' if ok else 'TOO LONG'}")
if len(blocks) != 8:
    print(f"expected 8 blocks, found {len(blocks)}"); bad += 1
sys.exit(1 if bad else 0)
