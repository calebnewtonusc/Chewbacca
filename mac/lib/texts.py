#!/usr/bin/env python3
"""Read iMessage/SMS history as structured data, with real names and real text.

Layer 1. No UI, no screenshots, no Messages window. Reads chat.db directly and
decodes the attributedBody blob that holds most modern message bodies.

Requires Full Disk Access on the host app. Read-only, always.
"""
import argparse, glob, json, os, re, sqlite3, sys
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from attributed_body import message_text

CHAT_DB = os.path.expanduser("~/Library/Messages/chat.db")
AB_GLOB = os.path.expanduser(
    "~/Library/Application Support/AddressBook/Sources/*/AddressBook-v22.abcddb")
APPLE_EPOCH = 978307200  # 2001-01-01, not 1970. Every naive query gets this wrong.


def _norm(handle):
    """Last 10 digits, so +1 310 555 1234 and 3105551234 match."""
    d = re.sub(r"\D", "", handle or "")
    return d[-10:] if len(d) >= 10 else (handle or "").lower()


def contacts():
    """Map normalized phone/email -> display name, across all address book sources."""
    out = {}
    for path in glob.glob(AB_GLOB):
        try:
            db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
            for table, col in (("ZABCDPHONENUMBER", "ZFULLNUMBER"),
                               ("ZABCDEMAILADDRESS", "ZADDRESS")):
                try:
                    rows = db.execute(
                        f"SELECT {col}, r.ZFIRSTNAME, r.ZLASTNAME, r.ZORGANIZATION "
                        f"FROM {table} t JOIN ZABCDRECORD r ON t.ZOWNER = r.Z_PK").fetchall()
                except sqlite3.Error:
                    continue
                for value, first, last, org in rows:
                    if not value:
                        continue
                    name = " ".join(p for p in (first, last) if p) or org
                    if name:
                        out.setdefault(_norm(value), name)
            db.close()
        except sqlite3.Error:
            continue
    return out


def read(days=7, limit=2000, who=None, unanswered=False, direct=False,
         db_path=CHAT_DB):
    if not os.path.exists(db_path):
        raise SystemExit(f"no chat.db at {db_path}")
    try:
        db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    except sqlite3.OperationalError as e:
        raise SystemExit(f"cannot open chat.db ({e}). Full Disk Access is probably missing.")

    cutoff = (datetime.now() - timedelta(days=days)).timestamp() - APPLE_EPOCH
    try:
        rows = db.execute("""
            SELECT m.rowid, m.date, m.is_from_me, m.text, m.attributedBody,
                   h.id, c.display_name, c.chat_identifier, m.cache_has_attachments,
                   m.associated_message_type
            FROM message m
            LEFT JOIN handle h ON m.handle_id = h.ROWID
            LEFT JOIN chat_message_join cmj ON m.ROWID = cmj.message_id
            LEFT JOIN chat c ON cmj.chat_id = c.ROWID
            WHERE m.date/1000000000 > ?
            ORDER BY m.date DESC LIMIT ?""", (cutoff, limit if limit and limit > 0 else -1)).fetchall()
    except sqlite3.DatabaseError as e:
        raise SystemExit(f"query failed: {e}")

    book = contacts()
    msgs = []
    for (rid, date, from_me, text, blob, handle, chat_name,
         chat_id, has_attach, assoc) in rows:
        body = message_text(text, blob)
        if not body and not has_attach:
            continue
        who_key = handle or chat_id or ""
        name = chat_name or book.get(_norm(who_key)) or who_key or "unknown"
        msgs.append({
            "id": rid,
            "at": datetime.fromtimestamp(date / 1e9 + APPLE_EPOCH).isoformat(timespec="minutes"),
            "with": name,
            "handle": handle or chat_id,
            "from_me": bool(from_me),
            "text": body or "[attachment]",
            # 2000-2005 = a tapback was added, 3000-3005 = removed. These are
            # "Loved an image", not a message, and treating them as one is how a
            # follow-up list fills up with obligations that do not exist.
            "reaction": bool(assoc),
            "attachment_only": not body and bool(has_attach),
        })

    if direct:
        # One-on-one only. A group chat's last message is usually not aimed at
        # you, so it inflates an "unanswered" list with obligations you do not have.
        msgs = [m for m in msgs if (m["handle"] or "").startswith(("+", "e:"))
                or "@" in (m["handle"] or "")]

    if who:
        needle = who.lower()
        msgs = [m for m in msgs
                if needle in (m["with"] or "").lower()
                or needle in (m["handle"] or "").lower()]

    if unanswered:
        # Threads where the most recent message is not from me. That is the
        # cheap, honest definition of a ball still in your court.
        # A tapback or a bare attachment is not someone waiting on you, so it
        # cannot be the message that makes a thread "open". Find the last real
        # one instead.
        last = {}
        for m in msgs:  # already newest-first
            if m["reaction"] or m["attachment_only"]:
                continue
            last.setdefault(m["handle"], m)
        open_handles = {h for h, m in last.items() if not m["from_me"]}
        msgs = [m for m in msgs
                if m["handle"] in open_handles and not m["reaction"]]

    return list(reversed(msgs))  # oldest-first reads better for an LLM


def main():
    p = argparse.ArgumentParser(description="Read iMessage history as structured data")
    p.add_argument("--days", type=int, default=7)
    p.add_argument("--limit", type=int, default=2000,
                   help="0 or less means no cap, for a full-history backfill")
    p.add_argument("--who", help="filter by contact name or handle")
    p.add_argument("--unanswered", action="store_true",
                   help="only threads where they spoke last")
    p.add_argument("--direct", action="store_true",
                   help="one-on-one threads only, no group chats")
    p.add_argument("--json", action="store_true")
    a = p.parse_args()

    msgs = read(days=a.days, limit=a.limit, who=a.who,
                unanswered=a.unanswered, direct=a.direct)
    if a.json:
        print(json.dumps(msgs, indent=2))
        return
    if not msgs:
        print("no messages matched")
        return
    current = None
    for m in msgs:
        if m["with"] != current:
            current = m["with"]
            print(f"\n=== {current} ===")
        arrow = "->" if m["from_me"] else "<-"
        print(f"{m['at']} {arrow} {m['text']}")


if __name__ == "__main__":
    main()
