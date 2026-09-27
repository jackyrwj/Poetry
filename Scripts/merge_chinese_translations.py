#!/usr/bin/env python3
"""Merge zh-translation-parts/*.json into ClassicPoemTranslation-zh.json.

Fails loudly unless the merged keys exactly match ClassicPoemTranslation-en.json,
so the resource can never silently fall behind the source data.
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARTS_DIR = os.path.join(ROOT, "Scripts", "zh-translation-parts")
OUT = os.path.join(ROOT, "Poetry", "ClassicPoemTranslation-zh.json")
EN = os.path.join(ROOT, "Poetry", "ClassicPoemTranslation-en.json")

merged = {}
for path in sorted(glob.glob(os.path.join(PARTS_DIR, "*.json"))):
    with open(path) as f:
        part = json.load(f)
    overlap = set(merged) & set(part)
    if overlap:
        sys.exit(f"Duplicate keys across parts: {sorted(overlap)[:5]}")
    merged.update(part)
    print(f"{os.path.basename(path)}: {len(part)} entries")

expected = set(json.load(open(EN))["translations"])
missing = sorted(expected - set(merged))
extra = sorted(set(merged) - expected)
if missing or extra:
    sys.exit(f"Key mismatch. missing={missing[:10]} extra={extra[:10]}")

bad = [k for k, v in merged.items() if not isinstance(v, str) or not v.strip()]
if bad:
    sys.exit(f"Empty or invalid translations: {bad[:5]}")

resource = {
    "formatVersion": 1,
    "language": "zh",
    "generatedAt": "2026-09-27",
    "translations": {k: merged[k] for k in sorted(merged)},
}
with open(OUT, "w") as f:
    json.dump(resource, f, ensure_ascii=False, indent=1)
    f.write("\n")
print(f"Wrote {OUT} with {len(merged)} entries")
