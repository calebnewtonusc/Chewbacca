#!/usr/bin/env python3
"""Fetch the transcript and chat-log files attached to each lesson.

The course publishes its own transcript per workshop, which beats both
Wistia captions and whisper: it is the publisher's text, already punctuated
and speaker-labelled, so nothing is reconstructed from audio. The files sit
on a public CDN, so this half needs no session and runs in parallel.

  downloads.py scan     # list what it would fetch, write nothing
  downloads.py apply    # fetch into data/downloads/
  downloads.py apply --chat   # include the chat logs too
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENTS = ROOT / "data" / "contents"
COURSE = ROOT / "data" / "course.json"
OUT = ROOT / "data" / "downloads"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/153.0 Safari/537.36"

WORKERS = 6
TRANSCRIPT = re.compile(r"transcript", re.I)
CHATLOG = re.compile(r"chat\s*log", re.I)


def slugify(text: str) -> str:
    # Chapter names carry emoji; strip to ASCII word characters so the
    # directory names stay typeable and stable across runs.
    text = re.sub(r"[^\w\s-]", "", text.lower()).strip()
    return re.sub(r"[\s_-]+", "-", text)[:60].strip("-") or "untitled"


def module_map() -> dict[int, tuple[int, str]]:
    """content_id -> (chapter position, chapter name)."""
    tree = json.loads(COURSE.read_text())
    chapters = {c["id"]: c["name"] for c in tree["chapters"]}
    order = {cid: i for i, cid in enumerate(tree["course"]["chapter_ids"])}
    out = {}
    for c in tree["contents"]:
        ch = c.get("chapter_id")
        out[c["id"]] = (order.get(ch, 98) + 1, chapters.get(ch, "Uncategorized"))
    return out


def plan(include_chat: bool) -> list[dict]:
    mods = module_map()
    jobs: list[dict] = []
    for path in sorted(CONTENTS.glob("*.json")):
        payload = json.loads(path.read_text())
        content = payload.get("_content", {})
        cid = content.get("id")
        pos, chapter = mods.get(cid, (99, "Uncategorized"))
        module_dir = f"{pos:02d}-{slugify(chapter)}"

        for dl in payload.get("download_files") or []:
            name = dl.get("file_name") or ""
            url = dl.get("download_url")
            if not url:
                continue
            is_transcript = bool(TRANSCRIPT.search(name))
            is_chat = bool(CHATLOG.search(name))
            if not is_transcript and not (include_chat and is_chat):
                continue
            suffix = Path(urllib.parse.urlparse(url).path).suffix or ".bin"
            kind = "transcript" if is_transcript else "chatlog"
            jobs.append({
                "content_id": cid,
                "position": content.get("position", 0),
                "url": url,
                "dest": OUT / module_dir / f"{content.get('position', 0):02d}-{slugify(content.get('name', ''))}--{kind}{suffix}",
                "chapter": chapter,
                "lesson": content.get("name", ""),
                "kind": kind,
                "file_name": name,
            })
    return jobs


def fetch(job: dict) -> tuple[dict, str]:
    dest: Path = job["dest"]
    if dest.exists() and dest.stat().st_size > 0:
        return job, "exists"
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(job["url"], headers={"User-Agent": UA})
    tmp = dest.with_suffix(dest.suffix + ".part")
    try:
        with urllib.request.urlopen(req, timeout=120) as resp, tmp.open("wb") as fh:
            while chunk := resp.read(1 << 20):
                fh.write(chunk)
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
        tmp.unlink(missing_ok=True)
        return job, f"failed: {exc}"
    if tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        return job, "failed: empty"
    tmp.rename(dest)
    return job, f"ok {dest.stat().st_size:,}b"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["scan", "apply"])
    ap.add_argument("--chat", action="store_true", help="also fetch chat logs")
    args = ap.parse_args()

    jobs = plan(args.chat)
    print(f"{len(jobs)} files across {len({j['dest'].parent for j in jobs})} modules\n")

    if args.mode == "scan":
        for j in sorted(jobs, key=lambda x: str(x["dest"])):
            print(f"  {j['dest'].relative_to(ROOT)}")
            print(f"      <- {j['file_name']}")
        return

    manifest = {
        str(j["dest"].relative_to(ROOT)): {
            "content_id": j["content_id"], "module": j["chapter"],
            "lesson": j["lesson"], "kind": j["kind"], "file_name": j["file_name"],
        }
        for j in jobs
    }
    (ROOT / "data" / "manifest.json").write_text(json.dumps(manifest, indent=2))

    ok = failed = 0
    with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
        for job, status in pool.map(fetch, jobs):
            if status.startswith("failed"):
                failed += 1
                print(f"  FAIL {job['chapter']} / {job['lesson']}: {status}")
            else:
                ok += 1
    print(f"\n{ok} fetched or already present, {failed} failed")


if __name__ == "__main__":
    main()
