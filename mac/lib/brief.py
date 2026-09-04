#!/usr/bin/env python3
"""Chewbacca operator brief: gather the state of the user's morning as structured data.

Pulls from the reliable, cheap layers - email (bounded AppleScript), texts
(chat.db with the attributedBody decoder), and calendar (the Calendar DB
directly). It does NOT triage. It hands the agent clean data; the /brief skill
decides what is urgent and how to deliver it. Gathering and judging are separate
so the judging is auditable.

    chewie brief            human-readable dump
    chewie brief --json     structured, for the agent to triage
"""
import argparse, glob, json, os, subprocess, sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from texts import read as read_texts

CAL_DB = os.path.expanduser(
    "~/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb")
APPLE_EPOCH = 978307200


def _run(cmd, timeout=25):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None


def emails(limit=20):
    """Recent inbox messages, newest first. Bounded AppleScript: instant even on a
    huge mailbox, where a `whose` filter would hang. Read state is best-effort."""
    script = ('\n'
      'tell application "Mail"\n'
      '  set AppleScript\'s text item delimiters to tab\n'
      '  set out to ""\n'
      '  set n to (count of messages of inbox)\n'
      f'  if n > {limit} then set n to {limit}\n'
      '  repeat with i from 1 to n\n'
      '    set m to message i of inbox\n'
      '    try\n'
      '      set flag to "1"\n'
      '      if (read status of m) is true then set flag to "0"\n'
      '      set out to out & flag & tab & (sender of m) & tab & (subject of m) & tab & (date received of m as string) & linefeed\n'
      '    end try\n'
      '  end repeat\n'
      '  return out\n'
      'end tell')
    r = _run(["osascript", "-e", script], timeout=20)
    if not r or r.returncode != 0:
        # Mail unreachable or slow. Report honestly rather than fabricating.
        return {"available": False, "reason": (r.stderr.strip() if r else "timed out"), "items": []}
    items = []
    for line in r.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) >= 4:
            unread, sender, subject, when = parts[0], parts[1], parts[2], parts[3]
            items.append({"unread": unread == "1", "from": sender.strip(),
                          "subject": subject.strip(), "at": when.strip()})
    return {"available": True, "items": items}


def calendar_today():
    if not os.path.exists(CAL_DB):
        return {"available": False, "reason": "no calendar db", "items": []}
    q = ("SELECT ci.summary, "
         "datetime(ci.start_date + 978307200,'unixepoch','localtime'), "
         "datetime(ci.end_date + 978307200,'unixepoch','localtime'), ci.all_day "
         "FROM CalendarItem ci "
         "WHERE date(ci.start_date + 978307200,'unixepoch','localtime') = date('now','localtime') "
         "ORDER BY ci.start_date")
    r = _run(["sqlite3", f"file:{CAL_DB}?mode=ro", q], timeout=10)
    if not r or r.returncode != 0:
        return {"available": False, "reason": (r.stderr.strip() if r else "timed out"), "items": []}
    items = []
    for line in r.stdout.splitlines():
        p = line.split("|")
        if len(p) >= 3 and p[0]:
            items.append({"summary": p[0], "start": p[1], "end": p[2],
                          "all_day": p[3] == "1" if len(p) > 3 else False})
    return {"available": True, "items": items}


def gather(days=1):
    try:
        texts = read_texts(days=days, unanswered=True, direct=True)
    except SystemExit as e:
        texts = {"available": False, "reason": str(e)}
    open_threads = {}
    if isinstance(texts, list):
        for m in texts:
            if not m["from_me"] and m["text"] != "[attachment]":
                open_threads[m["with"]] = m  # newest wins, list is oldest-first
    return {
        "generated_at": datetime.now().isoformat(timespec="minutes"),
        "email": emails(),
        "texts": {"available": isinstance(texts, list),
                  "open_threads": [
                      {"with": k, "last": v["text"][:200], "at": v["at"]}
                      for k, v in open_threads.items()]},
        "calendar": calendar_today(),
    }


def render(b):
    print(f"CHEWBACCA BRIEF  {b['generated_at']}\n")
    cal = b["calendar"]
    print("TODAY")
    if not cal["available"]:
        print(f"  (calendar unavailable: {cal.get('reason')})")
    elif not cal["items"]:
        print("  nothing on the calendar")
    else:
        for e in cal["items"]:
            when = "all day" if e["all_day"] else e["start"][11:16]
            print(f"  {when}  {e['summary']}")
    print()
    tx = b["texts"]
    print(f"TEXTS WAITING ON YOU ({len(tx['open_threads'])})")
    for t in tx["open_threads"][:12]:
        print(f"  {t['with'][:28]:28}  {t['last'][:70]}")
    print()
    em = b["email"]
    if not em["available"]:
        print(f"EMAIL  (unavailable: {em.get('reason')})")
    else:
        unread = [e for e in em["items"] if e["unread"]]
        print(f"RECENT EMAIL ({len(unread)} unread of {len(em['items'])} shown)")
        for e in em["items"][:12]:
            mark = "*" if e["unread"] else " "
            frm = e["from"][:30]
            print(f"  {mark} {frm:30}  {e['subject'][:50]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=1)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    b = gather(days=a.days)
    print(json.dumps(b, indent=2) if a.json else "", end="")
    if not a.json:
        render(b)


if __name__ == "__main__":
    main()
