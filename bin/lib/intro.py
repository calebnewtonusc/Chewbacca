"""Warm-intro paths: who you know who can get you to a goal.

After jexp/neo4jev, where each hop of a graph walk is a Jev judgment over the
outgoing edges and the walk keeps a beam of the best paths. The graph here is
the one Chewbacca already holds:

    you --warmth--> person (people.db) --works at / circle / fact--> org
                                                  org --> contact (contacts.db)

people.db has no person-to-person edges, so every path is two hops: a person
you know, then an organization in the contacts index where the goal lives.

Split by Canny's rule. A person whose company IS a target organization is a
fact and is listed first with no model call. Everything else is a judgment:
Jev scores each candidate bridge (hop 1), keeps a beam, then chooses which
target organization each bridge is closest to (hop 2). Read-only: it opens
both databases with mode=ro and contacts nobody.
"""
from __future__ import annotations

import glob
import os
import re
import sqlite3
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import jev  # noqa: E402

# Bridges scored per run, warmest first. Forty calls at two workers stayed
# within a few seconds on 2026-09-24.
CANDIDATES = 40
BEAM = 5
# Target organizations offered to one Choice. Guessed, never measured: a
# menu much longer than this is a harder question than the walk needs.
ORGS = 10
FACTS_PER_PERSON = 5
WORKERS = 2
# Guessed, never measured: below this a bridge is not worth listing.
BRIDGE_FLOOR = 0.5


def people_db() -> Path:
    return Path(os.environ.get("PEOPLE_DIR", Path.home() / ".chewbacca" / "people")) / "people.db"


def contacts_db() -> Path | None:
    """FOUND, NOT HARDCODED: $CONTACTS_DB, the Chewbacca home, or a brain."""
    for p in [os.environ.get("CONTACTS_DB"), str(Path.home() / ".chewbacca/contacts/contacts.db"),
              *sorted(glob.glob(str(Path.home() / "dev/*-context/professional-contacts/contacts.db")))]:
        if p and Path(p).is_file():
            return Path(p)
    return None


def ro(path: Path) -> sqlite3.Connection:
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    return con


def fts_query(goal: str) -> str:
    words = [w for w in re.findall(r"[A-Za-z0-9]{3,}", goal.lower())
             if w not in {"the", "and", "for", "who", "can", "get", "someone", "intro", "introduce",
                          "into", "with", "that", "from", "any", "investor", "investors"}]
    return " OR ".join(f'"{w}"' for w in words) or '""'


def targets(con: sqlite3.Connection, query: str, limit: int = 200) -> dict[str, list[dict]]:
    """Target contacts grouped by organization, best grade first."""
    rows = con.execute(
        """SELECT c.full_name, c.title, c.organization, c.grade, c.grade_score, c.email, c.linkedin
           FROM contacts_fts f JOIN contacts c ON c.rowid = f.rowid
           WHERE contacts_fts MATCH ? AND c.organization != ''
           ORDER BY CAST(c.grade_score AS REAL) DESC LIMIT ?""", (query, limit)).fetchall()
    orgs: dict[str, list[dict]] = {}
    for r in rows:
        orgs.setdefault(r["organization"], []).append(dict(r))
    return orgs


def bridges(con: sqlite3.Connection, limit: int = CANDIDATES) -> list[dict]:
    """Your warmest people who have an edge to follow.

    A name with no company, role, circle or fact gives a walk nothing to
    judge. On 2026-09-24 people.db held 949 people, 19 with a company and 7
    with a fact, and the warmest forty were almost all bare names: every
    bridge scored under the floor and the first real run found no path.
    """
    rows = con.execute(
        """SELECT p.id, p.name, p.company, p.role, p.location, p.how_we_met,
                  COALESCE(s.warmth, 0) AS warmth
           FROM people p LEFT JOIN person_scores s ON s.person_id = p.id
           WHERE p.deleted_at IS NULL AND (
             COALESCE(p.company, '') != '' OR COALESCE(p.role, '') != ''
             OR COALESCE(p.how_we_met, '') != ''
             OR EXISTS (SELECT 1 FROM circle_members m WHERE m.person_id = p.id)
             OR EXISTS (SELECT 1 FROM observations o WHERE o.person_id = p.id
                        AND o.kind = 'fact' AND o.deleted_at IS NULL))
           ORDER BY warmth DESC, COALESCE(s.base_score, 0) DESC LIMIT ?""", (limit,)).fetchall()
    out = []
    for r in rows:
        circles = [c[0] for c in con.execute(
            """SELECT c.name FROM circle_members m JOIN circles c ON c.id = m.circle_id
               WHERE m.person_id = ? AND c.deleted_at IS NULL""", (r["id"],))]
        facts = [f[0] for f in con.execute(
            """SELECT body FROM observations WHERE person_id = ? AND deleted_at IS NULL
               AND kind = 'fact' AND modality = 'actual' ORDER BY observed_at DESC LIMIT ?""",
            (r["id"], FACTS_PER_PERSON))]
        out.append({**dict(r), "circles": circles, "facts": facts})
    return out


def profile(p: dict) -> dict:
    """What Jev sees of a person. No name: it does not help the judgment, and
    the person never chose to have it sent to a cloud API."""
    return {k: p[k] for k in ("company", "role", "location", "how_we_met", "circles", "facts") if p.get(k)}


def norm(org: str | None) -> str:
    return re.sub(r"\b(inc|llc|ltd|capital|ventures|partners|group|co)\b|[^a-z0-9]", "", (org or "").lower())


def walk(goal: str, people: list[dict], orgs: dict[str, list[dict]], ask=None) -> list[dict]:
    """Paths, fact paths first, then judged paths by score."""
    paths = []
    by_norm = {norm(o): o for o in orgs if norm(o)}
    for p in people:
        org = by_norm.get(norm(p.get("company")))
        if org:
            paths.append({"via": "fact", "score": 1.0, "person": p["name"], "org": org,
                          "why": f"{p['name']} works at {p.get('company')}", "contacts": orgs[org][:3]})
    matched = {x["person"] for x in paths}
    rest = [p for p in people if p["name"] not in matched]
    if not rest or not orgs:
        return paths
    if ask is None:
        if not (jev.api_key() and jev.allowed()):
            return paths

        def ask(state, questions):
            return jev.ask(state, questions, timeout=3.0)

    def hop1(p):
        a = ask({"goal": goal, "person": profile(p)}, {"bridge": {"type": "noul", "instructions":
                "The user knows `person` personally. Could `person` plausibly introduce the user to "
                "someone who fits `goal`, through their work, their industry, their circles or "
                "what they have done? A shared city alone is not enough."}})
        return p, float(((a or {}).get("bridge") or {}).get("noul") or 0.0)

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        scored = sorted(pool.map(hop1, rest), key=lambda s: -s[1])
    beam = [(p, s) for p, s in scored[:BEAM] if s >= BRIDGE_FLOOR]
    menu = list(orgs)[:ORGS]
    criteria = {f"o{i}": o for i, o in enumerate(menu)}
    criteria["none"] = "none of these organizations"

    def hop2(item):
        p, s = item
        a = ask({"goal": goal, "person": profile(p)}, {"org": {"type": "choice", "instructions": {
                "question": "Which organization is `person` most likely able to reach for the user?",
                "note": "Judge by their work, industry and circles. Choose none if none is plausible."},
                "criteria": criteria}})
        ans = (a or {}).get("org") or {}
        pick = ans.get("choice")
        conf = float((ans.get("probabilities") or {}).get(pick, 0.0))
        return p, s, criteria.get(pick) if pick in criteria and pick != "none" else None, conf

    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        for p, s, org, conf in pool.map(hop2, beam):
            paths.append({"via": "jev", "score": round(s * (conf if org else 0.5), 3), "person": p["name"],
                          "org": org, "why": f"bridge {s:.2f}" + (f", org {conf:.2f}" if org else ", no org chosen"),
                          "contacts": orgs[org][:3] if org else []})
    return paths[:len(matched)] + sorted(paths[len(matched):], key=lambda x: -x["score"])
