#!/usr/bin/env python3
"""Render a Chewbacca run trace (JSONL) as a readable step list."""
import json, sys
mark = {"ok": "  ok", "fail": "FAIL", "skip": "skip", "info": "  .."}
for line in open(sys.argv[1]):
    try:
        e = json.loads(line)
    except json.JSONDecodeError:
        continue
    m = mark.get(e.get("status", "info"), "  ..")
    step = e.get("step", "?")
    detail = e.get("detail", "")
    ms = e.get("ms")
    t = f" ({ms}ms)" if ms is not None else ""
    print(f"{m}  {step:20}{t}  {detail}")
