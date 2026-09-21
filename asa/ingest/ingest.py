#!/usr/bin/env python3
"""Turn a raw course dump into one transcript file per lesson.

Split in two on purpose. `scan` reads the dump, resolves every video id and
reports what it would write, touching nothing. `apply` writes. The preview a
human approves is then exactly the work that happens.

  ingest.py scan
  ingest.py apply
"""
from __future__ import annotations

import concurrent.futures
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import thinkific  # noqa: E402
import wistia  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DUMP = ROOT / "data" / "course_raw.json"
TRANSCRIPTS = ROOT / "transcripts"
PENDING = ROOT / "data" / "needs_whisper.json"

# Wistia is a CDN and tolerates parallel reads far better than Thinkific does,
# but 8 is where throughput stopped improving in testing on this connection.
WORKERS = 8


def load() -> tuple[list[thinkific.Lesson], dict[int, dict]]:
    if not DUMP.exists():
        sys.exit(f"missing {DUMP}\nRun the browser fetch first (see asa/README.md).")
    dump = json.loads(DUMP.read_text())
    lessons = thinkific.parse_course(dump["course"])
    details = {d["course_content"]["id"] if "course_content" in d else d.get("id"): d
               for d in dump.get("details", [])}
    # Thinkific has shipped both envelope shapes; index on whatever id is present.
    fixed: dict[int, dict] = {}
    for d in dump.get("details", []):
        cid = (d.get("course_content") or {}).get("id") or d.get("id")
        if cid:
            fixed[cid] = d
    return lessons, fixed or details


def resolve(lessons, details) -> list[thinkific.Lesson]:
    for lesson in lessons:
        payload = details.get(lesson.content_id)
        if payload:
            lesson.video_id, lesson.duration = thinkific.find_video(payload)
    return lessons


def front_matter(lesson: thinkific.Lesson, source: str) -> str:
    mins = f"{lesson.duration / 60:.1f}" if lesson.duration else ""
    return (
        "---\n"
        f"module: {lesson.chapter_name}\n"
        f"lesson: {lesson.name}\n"
        f"content_id: {lesson.content_id}\n"
        f"video_id: {lesson.video_id or ''}\n"
        f"minutes: {mins}\n"
        f"source: {source}\n"
        "---\n\n"
        f"# {lesson.name}\n\n"
        f"Module: {lesson.chapter_name}\n\n"
    )


def fetch_one(lesson: thinkific.Lesson) -> tuple[thinkific.Lesson, str | None]:
    if not lesson.video_id:
        return lesson, None
    raw = wistia.captions(lesson.video_id)
    return lesson, wistia.vtt_to_text(raw) if raw else None


def main(mode: str) -> None:
    lessons = resolve(*load())
    with_video = [l for l in lessons if l.video_id]
    print(f"{len(lessons)} lessons, {len(with_video)} with video\n")

    results = []
    with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
        for lesson, text in pool.map(fetch_one, with_video):
            results.append((lesson, text))

    results.sort(key=lambda r: (r[0].chapter_position, r[0].position))
    captioned = [(l, t) for l, t in results if t]
    missing = [l for l, t in results if not t]

    for lesson, text in captioned:
        path = TRANSCRIPTS / lesson.module_dir / f"{lesson.file_stem}.md"
        words = len(text.split())
        print(f"  {'write' if mode == 'apply' else 'would write'}  {path.relative_to(ROOT)}  ({words} words)")
        if mode == "apply":
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(front_matter(lesson, "wistia-captions") + text + "\n")

    print(f"\ncaptioned: {len(captioned)}   need whisper: {len(missing)}")
    for lesson in missing:
        print(f"  no captions: {lesson.chapter_name} / {lesson.name}")

    if mode == "apply":
        PENDING.parent.mkdir(parents=True, exist_ok=True)
        PENDING.write_text(json.dumps(
            [{"content_id": l.content_id, "video_id": l.video_id, "name": l.name,
              "chapter": l.chapter_name, "module_dir": l.module_dir,
              "file_stem": l.file_stem, "duration": l.duration} for l in missing],
            indent=2,
        ))
        print(f"\nwrote {PENDING.relative_to(ROOT)} for transcribe.py")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "scan"
    if mode not in ("scan", "apply"):
        sys.exit(__doc__)
    main(mode)
