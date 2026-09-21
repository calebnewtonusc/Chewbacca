#!/usr/bin/env python3
"""Convert downloaded transcripts into one markdown file per lesson.

PDF goes through pdftotext -layout, which keeps a speaker label on its own
line instead of folding it into the paragraph above. That matters here
because the whole corpus is multi-speaker workshop recordings and losing the
turn boundaries makes a transcript unquotable.

  to_text.py scan
  to_text.py apply
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "data" / "downloads"
CONTENTS = ROOT / "data" / "contents"
COURSE = ROOT / "data" / "course.json"
DEST = ROOT / "transcripts"

# Zoom exports put a page header and a bare page number on every page. Both
# land mid-sentence once the pages are concatenated, so they go before the
# paragraphs are rebuilt.
PAGE_NOISE = re.compile(r"^\s*(page\s+\d+(\s+of\s+\d+)?|\d{1,3})\s*$", re.I)
MULTISPACE = re.compile(r"[ \t]{2,}")
BLANKS = re.compile(r"\n{3,}")
SPEAKER = re.compile(r"^([A-Z][A-Za-z.'-]+(?:\s+[A-Z][A-Za-z.'-]+){0,3})\s*:\s*(.*)$")


def extract(path: Path) -> str | None:
    suffix = path.suffix.lower()
    if suffix == ".pdf":
        run = subprocess.run(["pdftotext", "-layout", str(path), "-"], capture_output=True)
        return run.stdout.decode("utf-8", "replace") if run.returncode == 0 else None
    if suffix in (".doc", ".docx", ".rtf"):
        run = subprocess.run(["textutil", "-convert", "txt", "-stdout", str(path)], capture_output=True)
        return run.stdout.decode("utf-8", "replace") if run.returncode == 0 else None
    if suffix in (".txt", ".md", ".vtt", ".srt"):
        return path.read_text(errors="replace")
    return None


# Every page of an exported transcript PDF repeats the same header line, and
# pdftotext drops it wherever the page broke, which is mid-sentence. It was
# 5.8% of this corpus and it split claims away from their qualifiers.
#
# Matching it with one pattern across 79 files failed twice: the header ends
# on the filename, and the exporter truncates that differently per file. The
# header is identical within a file, though, so the longest common prefix
# across its own occurrences is the header exactly. That cannot eat speech,
# because it only removes a literal the file already repeats verbatim.
PAGE_MARK = "Meeting Title:"
HEADER_MAX = 400


def repeated_header(text: str) -> str | None:
    starts = [m.start() for m in re.finditer(re.escape(PAGE_MARK), text)]
    if len(starts) < 2:
        return None
    chunks = [text[s:s + HEADER_MAX] for s in starts]
    first = chunks[0]
    n = 0
    while n < len(first) and all(c[n:n + 1] == first[n] for c in chunks):
        n += 1
    header = first[:n].rstrip()
    return header if len(header) > len(PAGE_MARK) + 10 else None


def strip_furniture(text: str) -> str:
    header = repeated_header(text)
    if header:
        text = text.replace(header, " ")
    # A lone header on a single-page export has no sibling to align against.
    text = re.sub(
        rf"{re.escape(PAGE_MARK)}.{{0,250}}?(?:TRANSCR|CHAT LOG)[A-Z ]*(?:\.\.\.)?"
        rf"(?:[\s\d._-]{{0,20}}\.(?:m4a|mp4|pdf))?",
        " ",
        text,
        flags=re.S,
    )
    return text


def clean(text: str) -> str:
    text = strip_furniture(text)
    lines = [MULTISPACE.sub(" ", l.rstrip()) for l in text.splitlines()]
    lines = [l for l in lines if not PAGE_NOISE.match(l)]
    out: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            if out and out[-1] != "":
                out.append("")
            continue
        # A new speaker starts a new block; a continuation line is folded into
        # the block above so paragraphs survive the page breaks.
        if SPEAKER.match(stripped):
            if out and out[-1] != "":
                out.append("")
            out.append(stripped)
        elif out and out[-1] not in ("",):
            out[-1] = f"{out[-1]} {stripped}"
        else:
            out.append(stripped)
    return BLANKS.sub("\n\n", "\n".join(out)).strip()


def manifest() -> dict[str, dict]:
    """Map a downloaded file's repo-relative path to its lesson metadata.

    Written by downloads.py at fetch time. Deriving it here from filenames
    instead would re-guess a mapping that was already known exactly, and
    would drift the moment a lesson is renamed upstream.
    """
    path = ROOT / "data" / "manifest.json"
    return json.loads(path.read_text()) if path.exists() else {}


def lesson_meta() -> dict[str, dict]:
    tree = json.loads(COURSE.read_text())
    chapters = {c["id"]: c["name"] for c in tree["chapters"]}
    meta = {}
    for path in CONTENTS.glob("*.json"):
        payload = json.loads(path.read_text())
        c = payload.get("_content", {})
        body = payload.get("lesson") or {}
        secs = (c.get("meta_data") or {}).get("duration_in_seconds")
        meta[str(c.get("id"))] = {
            "lesson": c.get("name", ""),
            "module": chapters.get(c.get("chapter_id"), ""),
            "minutes": round(secs / 60, 1) if secs else None,
            "video_url": body.get("video_url") or "",
        }
    return meta


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["scan", "apply"])
    args = ap.parse_args()

    files = sorted(p for p in SRC.rglob("*") if p.is_file() and "--transcript" in p.name)
    if not files:
        raise SystemExit(f"no transcripts in {SRC}; run downloads.py apply first")

    man = manifest()
    meta = lesson_meta()
    total_words = 0
    for path in files:
        raw = extract(path)
        if not raw or not raw.strip():
            print(f"  NO TEXT  {path.name}")
            continue
        text = clean(raw)
        words = len(text.split())
        total_words += words
        stem = path.name.split("--")[0]
        dest = DEST / path.parent.name / f"{stem}.md"
        print(f"  {'write' if args.mode == 'apply' else 'would write'}  "
              f"{dest.relative_to(ROOT)}  ({words:,} words)")
        if args.mode != "apply":
            continue
        info = man.get(str(path.relative_to(ROOT)), {})
        extra = meta.get(str(info.get("content_id")), {})
        minutes = extra.get("minutes")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(
            "---\n"
            f"module: {info.get('module', '')}\n"
            f"lesson: {info.get('lesson', '')}\n"
            f"content_id: {info.get('content_id', '')}\n"
            f"minutes: {minutes if minutes else ''}\n"
            f"words: {words}\n"
            f"source: course-transcript\n"
            f"source_file: {info.get('file_name', path.name)}\n"
            "---\n\n"
            f"# {info.get('lesson', dest.stem)}\n\n"
            f"Module: {info.get('module', '')}\n\n"
            + text + "\n"
        )

    print(f"\n{len(files)} transcripts, {total_words:,} words total")


if __name__ == "__main__":
    main()
