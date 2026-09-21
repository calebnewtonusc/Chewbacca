#!/usr/bin/env python3
"""The end state stays-compare must leave behind: a CSV with at least one
row per site that was read, every row with a price and a link, and a
recommendation that names a shortlist.

    verify.py <out dir>
"""
import csv
import json
import sys
from pathlib import Path


def verify(out: Path) -> list[str]:
    problems: list[str] = []
    table = out / "stays.csv"
    if not table.is_file():
        return [f"no {table}"]
    rows = list(csv.DictReader(table.open()))
    if not rows:
        problems.append("stays.csv has no rows")
    for i, row in enumerate(rows, 1):
        total = next((v for k, v in row.items() if k.startswith("Total for")), "")
        if not total:
            problems.append(f"row {i} ({row.get('Listing', '?')}) has no total")
        if not row.get("Link", "").startswith("http"):
            problems.append(f"row {i} ({row.get('Listing', '?')}) has no link")
    sites = {row["Site"] for row in rows}
    for raw in out.glob("raw-*.json"):
        cards = json.loads(raw.read_text()).get("cards", [])
        name = {"airbnb": "Airbnb", "booking": "Booking.com"}.get(raw.stem.removeprefix("raw-"), raw.stem)
        if cards and name not in sites:
            problems.append(f"{raw.name} had {len(cards)} cards but no row came from it")
    text = (out / "RECOMMENDATION.md").read_text() if (out / "RECOMMENDATION.md").is_file() else ""
    if "## Shortlist" not in text or not any(line.startswith("- ") for line in text.splitlines()):
        problems.append("RECOMMENDATION.md has no shortlist")
    return problems


if __name__ == "__main__":
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "~/Desktop/stays").expanduser()
    found = verify(out)
    print("\n".join(found) if found else f"ok  {out}")
    sys.exit(1 if found else 0)
