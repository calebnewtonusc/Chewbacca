"""intro: fact paths need no model, the beam keeps only plausible bridges,
hop 2 names an organization from the menu or none, and both databases are
opened read-only. Fictional fixture databases; Jev is a stub."""
import os
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bin" / "lib"))
import intro  # noqa: E402

PEOPLE = [  # id, name, company, role, warmth, circles, facts
    ("p1", "Dana Reyes", "Lonestar Ventures", "Associate", 0.9, ["Rice alumni"], ["Sources seed deals in fintech"]),
    ("p2", "Marco Lin", "Brightpath Bank", "Product lead", 0.8, ["fintech meetup"], ["Ran the bank's startup program"]),
    ("p3", "Jules Park", "Riverside Gym", "Coach", 0.95, ["gym"], ["Trains on Saturdays"]),
]
CONTACTS = [  # name, title, org, grade, score, sectors, state
    ("Ana Cho", "Partner", "Lonestar Ventures LLC", "A", "92", "fintech seed", "TX"),
    ("Ben Ortiz", "Principal", "Pecan Street Capital", "B", "80", "fintech payments", "TX"),
    ("Cy Hart", "Partner", "Harbor Seed Fund", "B", "75", "fintech lending", "TX"),
]


def build(tmp: Path):
    pdir = tmp / "people"
    pdir.mkdir()
    p = sqlite3.connect(pdir / "people.db")
    p.executescript("""
      CREATE TABLE people (id TEXT PRIMARY KEY, name TEXT, company TEXT, role TEXT, location TEXT,
        how_we_met TEXT, deleted_at TEXT);
      CREATE TABLE person_scores (person_id TEXT, warmth REAL, base_score REAL);
      CREATE TABLE circles (id TEXT, name TEXT, deleted_at TEXT);
      CREATE TABLE circle_members (circle_id TEXT, person_id TEXT);
      CREATE TABLE observations (person_id TEXT, body TEXT, kind TEXT, modality TEXT,
        observed_at TEXT, deleted_at TEXT);""")
    for pid, name, co, role, w, circles, facts in PEOPLE:
        p.execute("INSERT INTO people VALUES (?,?,?,?,?,?,NULL)", (pid, name, co, role, "Austin", "school"))
        p.execute("INSERT INTO person_scores VALUES (?,?,?)", (pid, w, w))
        for c in circles:
            p.execute("INSERT INTO circles VALUES (?,?,NULL)", (c, c))
            p.execute("INSERT INTO circle_members VALUES (?,?)", (c, pid))
        for f in facts:
            p.execute("INSERT INTO observations VALUES (?,?,'fact','actual','2026-09-01',NULL)", (pid, f))
    p.commit()
    c = sqlite3.connect(tmp / "contacts.db")
    c.executescript("""
      CREATE TABLE contacts (full_name TEXT, title TEXT, organization TEXT, grade TEXT, grade_score TEXT,
        sectors TEXT, city TEXT, state TEXT, country TEXT, email TEXT, linkedin TEXT);
      CREATE VIRTUAL TABLE contacts_fts USING fts5(full_name, title, organization, sectors, city, state,
        country, content='contacts', content_rowid='rowid');""")
    for n, t, o, g, s, sec, st in CONTACTS:
        c.execute("INSERT INTO contacts VALUES (?,?,?,?,?,?,'Austin',?,'US','','')", (n, t, o, g, s, sec, st))
    c.execute("INSERT INTO contacts_fts(contacts_fts) VALUES ('rebuild')")
    c.commit()
    return pdir, tmp / "contacts.db"


BY_COMPANY = {co: name for _, name, co, *_ in PEOPLE}


def stub(bridge_scores, org_pick):
    def ask(state, questions):
        assert "name" not in state["person"], "a name was sent to Jev"
        name = BY_COMPANY[state["person"]["company"]]
        if "bridge" in questions:
            return {"bridge": {"noul": bridge_scores.get(name, 0.0)}}
        crit = questions["org"]["criteria"]
        key = next((k for k, v in crit.items() if v == org_pick.get(name)), "none")
        return {"org": {"choice": key, "probabilities": {key: 0.9}}}
    return ask


def main():
    failures = 0

    def check(name, cond):
        nonlocal failures
        print(("  ok    " if cond else "  FAIL  ") + name)
        failures += 0 if cond else 1

    with tempfile.TemporaryDirectory() as t:
        pdir, cdb = build(Path(t))
        people = intro.bridges(intro.ro(pdir / "people.db"))
        orgs = intro.targets(intro.ro(cdb), intro.fts_query("a fintech seed investor in Texas"))
        check("the goal finds all three target orgs", len(orgs) == 3)
        check("bridges come warmest first with circles and facts",
              people[0]["name"] == "Jules Park" and people[1]["facts"] == ["Sources seed deals in fintech"])

        paths = intro.walk("fintech seed investor", people, orgs, ask=lambda s, q: None)
        check("a company match is a fact path even with Jev down",
              paths and paths[0]["via"] == "fact" and paths[0]["org"] == "Lonestar Ventures LLC")

        paths = intro.walk("fintech seed investor", people, orgs,
                           ask=stub({"Marco Lin": 0.85, "Jules Park": 0.1}, {"Marco Lin": "Pecan Street Capital"}))
        judged = [x for x in paths if x["via"] == "jev"]
        check("the beam drops a bridge below the floor", [x["person"] for x in judged] == ["Marco Lin"])
        check("hop 2 names the chosen org and its contacts",
              judged[0]["org"] == "Pecan Street Capital" and judged[0]["contacts"][0]["full_name"] == "Ben Ortiz")
        check("fact paths stay ahead of judged ones", paths[0]["via"] == "fact")

        none = intro.walk("fintech", people, orgs, ask=stub({"Marco Lin": 0.9}, {}))
        check("hop 2 may choose none", [x["org"] for x in none if x["via"] == "jev"] == [None])

        try:
            intro.ro(cdb).execute("DELETE FROM contacts")
            check("the contacts index is read-only", False)
        except sqlite3.OperationalError:
            check("the contacts index is read-only", True)

        env = dict(os.environ, PEOPLE_DIR=str(pdir), CONTACTS_DB=str(cdb), TYPESAFE_API_KEY="", HOME=t)
        out = subprocess.run([str(ROOT / "bin/intro"), "fintech seed investor in Texas"],
                             capture_output=True, text=True, env=env, timeout=30)
        check("the CLI prints the fact path with no key",
              out.returncode == 0 and "[fact 1.00] you -> Dana Reyes -> Lonestar Ventures LLC" in out.stdout)
    print()
    print("intro walks the graph it has and nothing else" if not failures else f"{failures} failed")
    return failures


if __name__ == "__main__":
    sys.exit(main())
