#!/usr/bin/env python3
"""Generate the bounded agent-neutral export, without scraping Claude state."""
import argparse
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "instructions/agent-neutral.md"
# Codex's default project instruction budget is 32 KiB, including ancestor files.
MAX_BYTES = 24 * 1024


def render():
    text = ("# AGENTS.md\n\nGenerated from `instructions/agent-neutral.md`. "
            "Edit that shared source, then run\n`python3 tools/agents_md.py`. "
            "Claude Code remains the primary agent.\n\n" + SOURCE.read_text(encoding="utf-8"))
    if len(text.encode("utf-8")) > MAX_BYTES:
        raise ValueError("agent-neutral instructions exceed the 24 KiB export budget")
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", nargs="?", type=Path, default=REPO)
    parser.add_argument("--check", action="store_true", help="verify freshness without writing")
    args = parser.parse_args()
    out = args.destination / "AGENTS.md"
    text = render()
    if args.check:
        if not out.is_file() or out.read_text(encoding="utf-8") != text:
            parser.exit(1, f"stale or missing {out}; run python3 tools/agents_md.py\n")
        print(f"current {out}")
    else:
        out.write_text(text, encoding="utf-8")
        print(f"wrote {out}, {len(text.encode('utf-8'))} bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
