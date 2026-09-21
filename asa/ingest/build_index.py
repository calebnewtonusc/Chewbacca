#!/usr/bin/env python3
"""Build asa/INDEX.md from the transcripts on disk.

The index is the only part of the corpus small enough to load into a
session, so it carries module, lesson, runtime, length and source, and
never lesson text.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRANSCRIPTS = ROOT / "transcripts"
INDEX = ROOT / "INDEX.md"


def front(path: Path) -> dict[str, str]:
    text = path.read_text()
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    meta: dict[str, str] = {}
    if match:
        for line in match.group(1).splitlines():
            if ":" in line:
                k, v = line.split(":", 1)
                meta[k.strip()] = v.strip()
    return meta


def main() -> None:
    files = sorted(TRANSCRIPTS.rglob("*.md"))
    if not files:
        raise SystemExit("no transcripts yet")

    by_module: dict[str, list[tuple[Path, dict]]] = {}
    for path in files:
        by_module.setdefault(path.parent.name, []).append((path, front(path)))

    words = sum(int(m.get("words", 0)) for v in by_module.values() for _, m in v)
    minutes = sum(float(m["minutes"]) for v in by_module.values() for _, m in v if m.get("minutes"))

    lines = [
        "# A2A Spring 2026: transcript index",
        "",
        f"{len(files)} transcripts across {len(by_module)} modules. "
        f"{words:,} words, {minutes / 60:.0f} hours of recorded workshops.",
        "",
        "Transcripts are the course's own published PDFs, not machine captions.",
        "They are local only and never committed. See README.md.",
        "",
    ]

    for module in sorted(by_module):
        items = sorted(by_module[module], key=lambda p: p[0].name)
        title = items[0][1].get("module") or module
        mod_words = sum(int(m.get("words", 0)) for _, m in items)
        lines += [f"## {title}", "", f"{len(items)} sessions, {mod_words:,} words", ""]
        for path, meta in items:
            runtime = f"{float(meta['minutes']):.0f} min" if meta.get("minutes") else "length unknown"
            lines.append(
                f"- [{meta.get('lesson', path.stem)}]({path.relative_to(ROOT)}) "
                f"({runtime}, {int(meta.get('words', 0)):,} words)"
            )
        lines.append("")

    INDEX.write_text("\n".join(lines))
    print(f"wrote INDEX.md: {len(files)} transcripts, {words:,} words, {minutes/60:.0f} hours")


if __name__ == "__main__":
    main()
