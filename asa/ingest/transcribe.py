#!/usr/bin/env python3
"""Whisper fallback for lessons Wistia has no captions for.

Reads data/needs_whisper.json, pulls the smallest playable asset, transcribes
it, and writes the same transcript shape ingest.py writes. Resumable: a lesson
whose transcript already exists is skipped, so an interrupted run costs only
the file it was on.

  transcribe.py            # every pending lesson
  transcribe.py --limit 3  # the first three, to sanity-check quality first
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import wistia  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PENDING = ROOT / "data" / "needs_whisper.json"
TRANSCRIPTS = ROOT / "transcripts"

# small.en is the quality/speed knee for clear single-speaker course audio on
# Apple silicon: base.en drops product names and numbers, medium.en roughly
# triples runtime for changes that do not survive the summarising pass.
MODEL = "small.en"


def download(url: str, dest: Path) -> bool:
    req = urllib.request.Request(url, headers={"User-Agent": wistia.UA})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp, dest.open("wb") as fh:
            while chunk := resp.read(1 << 20):
                fh.write(chunk)
        return dest.stat().st_size > 0
    except Exception as exc:  # noqa: BLE001 - network shapes vary, all fatal here
        print(f"    download failed: {exc}")
        return False


def transcribe(media: Path, workdir: Path) -> str | None:
    audio = workdir / "audio.wav"
    ff = subprocess.run(
        ["ffmpeg", "-y", "-i", str(media), "-ac", "1", "-ar", "16000", "-vn", str(audio)],
        capture_output=True,
    )
    if ff.returncode != 0 or not audio.exists():
        print(f"    ffmpeg failed: {ff.stderr.decode()[-200:]}")
        return None

    run = subprocess.run(
        ["whisper", str(audio), "--model", MODEL, "--language", "en",
         "--output_format", "txt", "--output_dir", str(workdir), "--fp16", "False"],
        capture_output=True,
    )
    out = workdir / "audio.txt"
    if run.returncode != 0 or not out.exists():
        print(f"    whisper failed: {run.stderr.decode()[-200:]}")
        return None
    return " ".join(out.read_text().split())


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int)
    args = ap.parse_args()

    if not PENDING.exists():
        sys.exit(f"no {PENDING}; run ingest.py apply first")
    pending = json.loads(PENDING.read_text())
    if args.limit:
        pending = pending[: args.limit]
    print(f"{len(pending)} lessons to transcribe with whisper {MODEL}\n")

    for i, item in enumerate(pending, 1):
        path = TRANSCRIPTS / item["module_dir"] / f"{item['file_stem']}.md"
        if path.exists():
            print(f"[{i}/{len(pending)}] skip (exists) {item['name']}")
            continue
        print(f"[{i}/{len(pending)}] {item['chapter']} / {item['name']}")

        url = wistia.best_audio_asset(item["video_id"])
        if not url:
            print("    no playable asset")
            continue

        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            media = work / "video.mp4"
            if not download(url, media):
                continue
            text = transcribe(media, work)

        if not text:
            continue
        mins = f"{item['duration'] / 60:.1f}" if item.get("duration") else ""
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "---\n"
            f"module: {item['chapter']}\n"
            f"lesson: {item['name']}\n"
            f"content_id: {item['content_id']}\n"
            f"video_id: {item['video_id']}\n"
            f"minutes: {mins}\n"
            "source: whisper-" + MODEL + "\n"
            "---\n\n"
            f"# {item['name']}\n\n"
            f"Module: {item['chapter']}\n\n" + text + "\n"
        )
        print(f"    wrote {path.relative_to(ROOT)} ({len(text.split())} words)")


if __name__ == "__main__":
    main()
