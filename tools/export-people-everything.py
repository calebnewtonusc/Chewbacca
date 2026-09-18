#!/usr/bin/env python3
"""Every record in the people db, one row each, grouped by person and in time order."""
import csv, sqlite3, os, datetime

DB = os.path.expanduser("~/.chewbacca/people/people.db")
OUT = os.path.expanduser(f"~/Downloads/people-everything-{datetime.date.today()}.csv")

con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
con.row_factory = sqlite3.Row
c = con.cursor()

def clean(v):
    return " ".join(str(v).split()) if v is not None else ""

def tier(s):
    s = s or 0
    if s >= 0.15: return "core"
    if s >= 0.08: return "close"
    if s >= 0.03: return "known"
    return "contact"

P, rank = {}, {}
for i, r in enumerate(c.execute("""select p.id, p.name, p.company, p.role, p.location, p.linkedin,
                                          p.phone, p.email, p.nickname, p.how_we_met, p.birthday,
                                          p.source, p.muted_at, p.muted_reason,
                                          s.base_score, s.warmth, s.last_interaction_at, s.completeness
                                   from people p left join person_scores s on s.person_id = p.id
                                   where p.deleted_at is null
                                   order by coalesce(s.base_score,0) desc, p.name collate nocase""")):
    P[r["id"]] = r
    rank[r["id"]] = i

UNKNOWN = len(rank) + 1_000_000   # unattributed rows sink to the bottom
circle_name = {r["id"]: r["name"] for r in c.execute("select id, name from circles where deleted_at is null")}

# content sits in column E so the text is visible without scrolling
HEADER = ["person_name", "record_type", "occurred_at", "direction", "content",
          "label", "channel", "modality", "evidence_source",
          "tier", "score_0_100", "company", "role", "location", "person_id", "record_id"]

def who(pid, fallback=""):
    p = P.get(pid)
    if not p:
        return [fallback or "(unattributed)", "", "", "", "", "", pid or ""]
    return [clean(p["name"]), tier(p["base_score"]), round((p["base_score"] or 0) * 100, 1),
            clean(p["company"]), clean(p["role"]), clean(p["location"]), pid]

rows = []
def add(pid, ts, rec, direction, content, label, channel, modality, src, rid, fallback="", first=False):
    n, tr, sc, co, ro, lo, p = who(pid, fallback)
    key = (rank.get(pid, UNKNOWN), "" if first else (ts or "9999"))
    rows.append((key, [n, rec, ts, direction, content, label, channel, modality, src,
                       tr, sc, co, ro, lo, p, rid]))

n = {}
def bump(k): n[k] = n.get(k, 0) + 1

for pid, p in P.items():
    bits = [f"{k}: {clean(p[k])}" for k in
            ("nickname", "linkedin", "phone", "email", "how_we_met", "birthday", "muted_reason")
            if p[k] not in (None, "", 0)]
    add(pid, clean(p["last_interaction_at"]), "profile", "", " | ".join(bits),
        "muted" if p["muted_at"] else "", "", "", clean(p["source"]), pid, first=True)
    bump("profile")

for r in c.execute("select msg_id, person_id, who, handle, from_me, body, sent_at, source, room from messages"):
    add(r["person_id"], clean(r["sent_at"]), "message", "sent" if r["from_me"] else "received",
        clean(r["body"]), clean(r["room"]), clean(r["source"]), "", "", r["msg_id"],
        fallback=clean(r["who"]) or clean(r["handle"]))
    bump("message")

for r in c.execute("select id, person_id, circle_id, kind, modality, source, body, created_at from observations"):
    add(r["person_id"], clean(r["created_at"]), "observation", "", clean(r["body"]),
        circle_name.get(r["circle_id"], "") if r["circle_id"] else "",
        clean(r["kind"]), clean(r["modality"]), clean(r["source"]), r["id"])
    bump("observation")

for r in c.execute("select id, person_id, channel, note, happened_at from interactions"):
    add(r["person_id"], clean(r["happened_at"]), "interaction", "", clean(r["note"]),
        "", clean(r["channel"]), "", "", r["id"])
    bump("interaction")

for r in c.execute("select person_id, key, value, updated_at from quick_facts"):
    add(r["person_id"], clean(r["updated_at"]), "quick_fact", "", clean(r["value"]),
        clean(r["key"]), "", "", "", "")
    bump("quick_fact")

for r in c.execute("select circle_id, person_id, added_at from circle_members"):
    add(r["person_id"], clean(r["added_at"]), "circle", "", "",
        circle_name.get(r["circle_id"], r["circle_id"]), "", "", "", r["circle_id"])
    bump("circle")

for r in c.execute("select person_id, kind, value from identities"):
    add(r["person_id"], "", "identity", "", clean(r["value"]), clean(r["kind"]), "", "", "", "")
    bump("identity")

rows.sort(key=lambda t: t[0])

with open(OUT, "w", newline="", encoding="utf-8-sig") as fh:
    w = csv.writer(fh)
    w.writerow(HEADER)
    w.writerows(r[1] for r in rows)

print(OUT)
for k, v in sorted(n.items(), key=lambda kv: -kv[1]):
    print(f"  {k:<12} {v:>7,}")
print(f"  {'TOTAL':<12} {sum(n.values()):>7,}")
