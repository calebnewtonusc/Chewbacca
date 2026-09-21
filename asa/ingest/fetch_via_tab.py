#!/usr/bin/env python3
"""Read authenticated course JSON out of a signed-in Chrome tab, without JS.

Chrome's "Allow JavaScript from Apple Events" cannot be turned on here: the
menu item ignores synthetic presses and there is no preference or policy to
set instead. AppleScript can still drive tabs, so this navigates a scratch
tab to a JSON endpoint and lifts the rendered text off the clipboard.

The cost is that it borrows the keyboard. A grab taken while the user is
typing captures whatever app had focus, so every payload is validated
against the shape its endpoint must return and a mismatch is retried rather
than written. Garbage fails loudly; it never lands on disk.

  fetch_via_tab.py course
  fetch_via_tab.py contents --kind Lesson
  fetch_via_tab.py contents --retry
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
HOST = "https://learn.uncommonbusiness.co"
SLUG = "a2a-spring2026"

# Thinkific keys the detail endpoints on contentable_id, not content id, and
# uses a different path per contentable type. The v2 course_contents path
# that older integrations use returns 404 on this school.
ENDPOINT = {
    "Lesson": ("lessons", "lesson"),
    "HtmlItem": ("html_items", "html_item"),
    "Quiz": ("quizzes", "quiz"),
    "Survey": ("surveys", "survey"),
    "Audio": ("audio", "audio"),
    "Pdf": ("pdfs", "pdf"),
    "Download": ("downloads", "download"),
    "Presentation": ("presentations", "presentation"),
    "Multimedia": ("multimedia", "multimedia"),
}

SETTLE = 0.5
KEY_GAP = 0.2
ATTEMPTS = 4

GRAB = '''
tell application "Google Chrome"
  activate
  set t to last tab of window 1
  set URL of t to "{url}"
  repeat 150 times
    if not (loading of t) then exit repeat
    delay 0.2
  end repeat
  delay {settle}
end tell
tell application "System Events" to tell process "Google Chrome"
  keystroke "a" using command down
  delay {gap}
  keystroke "c" using command down
  delay {gap}
end tell
return "ok"
'''


def osa(script: str) -> str:
    run = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if run.returncode != 0:
        raise RuntimeError(run.stderr.strip()[:200])
    return run.stdout.strip()


def clipboard() -> str:
    return subprocess.run(["pbpaste"], capture_output=True, text=True).stdout


def set_clipboard(text: str) -> None:
    subprocess.run(["pbcopy"], input=text, text=True)


def grab_json(url: str, required_key: str) -> tuple[dict | None, str]:
    """Return the parsed payload, or None plus the reason it was rejected.

    A sentinel is written to the clipboard first so a silently failed copy
    reads back as the sentinel instead of as the previous lesson.
    """
    reason = "unknown"
    for attempt in range(ATTEMPTS):
        sentinel = f"__grab_{time.time_ns()}__"
        set_clipboard(sentinel)
        osa(GRAB.format(url=url, settle=SETTLE + 0.25 * attempt, gap=KEY_GAP))
        text = clipboard().strip()

        if text == sentinel or not text:
            reason = "copy did not land"
        elif not text.startswith("{"):
            reason = "focus was elsewhere" if "\n" in text[:200] else f"not json: {text[:60]}"
        else:
            try:
                payload = json.loads(text)
            except json.JSONDecodeError:
                reason = "truncated json"
            else:
                if required_key in payload:
                    return payload, "ok"
                reason = f"missing key {required_key}"
        time.sleep(0.5)
    return None, reason


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["course", "contents"])
    ap.add_argument("--kind", help="only this contentable_type")
    ap.add_argument("--retry", action="store_true", help="re-attempt items with no file")
    args = ap.parse_args()

    DATA.mkdir(parents=True, exist_ok=True)
    saved = clipboard()
    osa('tell application "Google Chrome" to activate')
    osa('tell application "Google Chrome" to make new tab at end of tabs of window 1 '
        'with properties {URL:"about:blank"}')
    osa('tell application "Google Chrome" to set active tab index of window 1 to (count of tabs of window 1)')

    try:
        if args.what == "course":
            payload, why = grab_json(f"{HOST}/api/course_player/v2/courses/{SLUG}", "course")
            if not payload:
                sys.exit(f"could not read the course tree: {why}")
            (DATA / "course.json").write_text(json.dumps(payload, indent=2))
            print(f"course.json: {len(payload.get('contents', []))} contents")
            return

        tree = json.loads((DATA / "course.json").read_text())
        out = DATA / "contents"
        out.mkdir(exist_ok=True)

        items = tree["contents"]
        if args.kind:
            items = [c for c in items if c.get("contentable_type") == args.kind]

        failed: list[tuple[int, str, str]] = []
        done = skipped = 0

        for n, content in enumerate(items, 1):
            cid = content["id"]
            kind = content.get("contentable_type")
            dest = out / f"{cid}.json"
            if dest.exists() and not args.retry:
                skipped += 1
                continue
            if kind not in ENDPOINT:
                print(f"[{n}/{len(items)}] unsupported type {kind} for {cid}")
                continue

            path, key = ENDPOINT[kind]
            payload, why = grab_json(
                f"{HOST}/api/course_player/v2/{path}/{content['contentable_id']}", key
            )
            name = content.get("name", "")[:46]
            if not payload:
                failed.append((cid, name, why))
                print(f"[{n}/{len(items)}] FAILED {name}  ({why})")
                continue

            payload["_content"] = content
            dest.write_text(json.dumps(payload, indent=2))
            done += 1
            print(f"[{n}/{len(items)}] {name}")

        print(f"\nfetched {done}, skipped {skipped}, failed {len(failed)}")
        for cid, name, why in failed:
            print(f"  {cid}  {name}  ({why})")
        if failed:
            print("\nRe-run with --retry once the machine is idle.")
    finally:
        try:
            osa('tell application "Google Chrome" to close (last tab of window 1)')
        except RuntimeError:
            pass
        set_clipboard(saved)


if __name__ == "__main__":
    main()
