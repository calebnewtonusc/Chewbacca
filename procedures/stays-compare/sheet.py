#!/usr/bin/env python3
"""The sheet: stays.csv and RECOMMENDATION.md from one run, as the text of a
single spreadsheet tab, ready to become a Google Sheet.

    sheet.py <out dir> [--note note.md] > sheet.csv

The top block is the run (city, dates, guests, budget), then the note if
one is given (the judgment, written by a person or the model for this
run), then the table with a clickable link per row. Formulas are written
as text starting with "="; Google Sheets evaluates them when a CSV is
imported or pasted.

How it becomes a Google Sheet:

- In a Claude Code session with the Google Drive connector: create a file
  with this text as text/csv; Drive converts it to a Sheet.
- Without one (the voice): a `sheets.new` tab in the person's own Chrome,
  filled through chrome-js. Needs "Allow JavaScript from Apple Events" on
  in Chrome; not built until that is on.
"""
from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
from pathlib import Path


def build(out: Path, note: str = "") -> str:
    rows = list(csv.reader((out / "stays.csv").open()))
    header, body = rows[0], rows[1:]
    rec = (out / "RECOMMENDATION.md").read_text() if (out / "RECOMMENDATION.md").is_file() else ""
    buf = io.StringIO()
    w = csv.writer(buf)
    first = rec.splitlines()[0].lstrip("# ").strip() if rec else "Where to stay"
    w.writerow([first])
    summary = next((l for l in rec.splitlines()[1:] if l.strip()), "")
    if summary:
        w.writerow([summary])
    for line in rec.splitlines():
        if line.startswith("Not read:") or "fit the budget" in line:
            w.writerow([line])
    if note.strip():
        w.writerow([])
        w.writerow(["Where to stay"])
        for para in [p for p in re.split(r"\n\s*\n", note.strip()) if p.strip()]:
            w.writerow([" ".join(para.split())])
    w.writerow([])
    link_at = header.index("Link")
    w.writerow(header[:link_at] + ["Open"] + ["URL"])
    for r in body:
        url = r[link_at]
        w.writerow(r[:link_at] + [f'=HYPERLINK("{url}", "{r[0]} listing")', url])
    w.writerow([])
    w.writerow([rec.strip().splitlines()[-1] if rec else ""])
    return buf.getvalue()


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--note", help="a markdown file with the recommendation in words")
    args = ap.parse_args(argv)
    note = Path(args.note).read_text() if args.note else ""
    sys.stdout.write(build(Path(args.out).expanduser(), note))
    return 0


if __name__ == "__main__":
    sys.exit(main())
