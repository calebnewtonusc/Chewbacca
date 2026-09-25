"""Blackboard Ultra by address: say where, get there, no clicking.

Every link shape here was read, not guessed. The course-ingest notes say
guessing an Ultra URL is worse than reading one, and on 2026-09-25 the person's
own Chrome history (35 visits, recorded while they clicked through all three
courses) gave the real ones. It also corrected the notes: a course's content
is at /outline, where course-ingest had /cl/outline.

The courses come from the coursework ledger (~/coursework/courses/*.yml,
`blackboard_internal_id`) and the items from course-ingest's last read
(~/coursework/.ingest/<school>/raw/course-*.json). Nothing here signs in or
reads Blackboard: it only builds the address and opens it.

Words decide first: a course name and a page word, or an item's own number
("homework 2"). Jev is asked only when the words leave it open ("where do I turn
in my anthropology paper"), with one choice over that course's pages and items.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import jev  # noqa: E402

COURSEWORK = Path(os.environ.get("COURSEWORK_DIR", str(Path.home() / "coursework")))
HOST = os.environ.get("BB_HOST", "acconline.austincc.edu")
SCHOOL = os.environ.get("BB_SCHOOL", "acc")
BASE = f"https://{HOST}"
# Read from the person's Chrome history, 2026-09-25.
GLOBAL_PAGES = {
    "activity": "/ultra/stream",
    "courses": "/ultra/course",
    "calendar": "/ultra/calendar",
}
COURSE_PAGES = {
    "content": "outline", "discussions": "engagement", "grades": "grades", "messages": "messages",
    "announcements": "announcements", "calendar": "calendar", "groups": "groups/enrollments",
    "achievements": "achievements",
}
PAGE_WORDS = [
    ("discussions", r"\bdiscussions?\b|\bdiscussion board\b|\bforum\b|\bposts?\b"),
    ("grades", r"\bgrades?\b|\bgradebook\b|\bscores?\b|\bmarks\b|\bhow am i doing\b"),
    ("announcements", r"\bannouncements?\b|\bnews\b"),
    ("messages", r"\bmessages?\b|\binbox\b"),
    ("calendar", r"\bcalendar\b|\bschedule\b|\bdue dates?\b"),
    ("groups", r"\bgroups?\b"),
    ("achievements", r"\bachievements?\b|\bbadges?\b"),
    ("content", r"\bcontent\b|\bmodules?\b|\bmaterials?\b|\bcourse page\b|\bhome page\b|\boutline\b|\bclass page\b"),
]
# Item shapes by content handler. Assessments and folders were opened by the
# person on 2026-09-25 at these addresses; a document takes the folder's route
# in Ultra and has not been seen yet. Discussions open from the Discussions
# page, whose address is known, because the discussion's own address is not.
ITEM_ROUTES = {
    "resource/x-bb-asmt-test-link": "assessment/{item}/overview?courseId={course}",
    "resource/x-bb-folder": "document/{item}?view=content&state=view",
    "resource/x-bb-document": "document/{item}?view=content&state=view",
    "resource/x-bb-lesson": "document/{item}?view=content&state=view",
    "resource/x-bb-file": "document/{item}?view=content&state=view",
    "resource/x-bb-courselink": "engagement",
}
NOISE = {"course evaluation", "online tutoring", "college policies & student support services"}
JEV_FLOOR = 0.6  # guessed, never measured; below it the choices are offered, not opened


def _yaml_field(text: str, key: str) -> str | None:
    m = re.search(rf"^{key}:\s*\"?([^\"\n]+)\"?\s*$", text, re.M)
    return m.group(1).strip() if m else None


def courses() -> list[dict]:
    out = []
    for f in sorted((COURSEWORK / "courses").glob("*.yml")):
        text = f.read_text(encoding="utf-8")
        cid = _yaml_field(text, "blackboard_internal_id")
        if not cid:
            continue
        code = _yaml_field(text, "code") or f.stem
        out.append({"key": f.stem, "code": code, "title": _yaml_field(text, "title") or code, "id": cid,
                    "bb": _yaml_field(text, "blackboard_id") or ""})
    return out


def items(course: dict) -> list[dict]:
    for f in (COURSEWORK / ".ingest" / SCHOOL / "raw").glob("course-*.json"):
        if course["bb"] and course["bb"] not in f.name:
            continue
        data = json.loads(f.read_text(encoding="utf-8"))
        rows = (data.get("contents") or {}).get("json") or []
        rows = rows.get("results", rows) if isinstance(rows, dict) else rows
        out, seen = [], set()
        for r in rows:
            handler = r.get("contentHandler")
            handler = handler.get("id") if isinstance(handler, dict) else handler
            title = " ".join((r.get("title") or "").split())
            if not title or title.lower() in NOISE or title.lower() in seen:
                continue
            seen.add(title.lower())
            link = (r.get("contentHandler") or {}).get("url") if isinstance(r.get("contentHandler"), dict) else None
            out.append({"id": r.get("id"), "title": title, "handler": handler, "url": link})
        return out
    return []


def course_for(words: str, all_courses: list[dict]) -> dict | None:
    hits = []
    for c in all_courses:
        subject = c["code"].split()[0].lower()
        names = {subject, c["key"].split("-")[0]} | {w for w in re.findall(r"[a-z]+", c["title"].lower()) if len(w) > 4}
        stems = {n[:5] for n in names if len(n) >= 5}
        tokens = set(re.findall(r"[a-z]+", words))
        if tokens & names or any(t[:5] in stems for t in tokens if len(t) >= 5):
            hits.append(c)
    return hits[0] if len(hits) == 1 else None


def page_for(words: str) -> str | None:
    for page, pattern in PAGE_WORDS:
        if re.search(pattern, words):
            return page
    return None


def item_url(course: dict, item: dict) -> str | None:
    if item["handler"] == "resource/x-bb-externallink" and item.get("url"):
        return item["url"]
    route = ITEM_ROUTES.get(item["handler"] or "")
    if not route:
        return None
    return f"{BASE}/ultra/courses/{course['id']}/" + route.format(item=item["id"], course=course["id"])


def item_by_words(words: str, pool: list[dict]) -> dict | None:
    """ "homework 2", "discussion 1", "final paper": the item's own words, unique."""
    m = re.search(r"\b(homework|hw|discussion|quiz|test|exam|chapter|module|unit|week|lesson|assignment)\s*#?\s*(\d+)\b", words)
    if m:
        kind = {"hw": "homework"}.get(m.group(1), m.group(1))
        hits = [i for i in pool if re.search(rf"\b{kind}\s*#?\s*{m.group(2)}\b", i["title"].lower())]
        return hits[0] if len(hits) == 1 else None
    hits = [i for i in pool if len(i["title"]) > 5 and i["title"].lower() in words]
    return hits[0] if len(hits) == 1 else None


def resolve(said: str, ask=None) -> dict:
    """{"url", "label"} to open, or {"ask": [...]} to offer, or {"why"}."""
    words = " ".join(said.lower().replace("’", "'").split())
    all_courses = courses()
    if not all_courses:
        return {"why": "no courses with a Blackboard id in ~/coursework"}
    course = course_for(words, all_courses)
    page = page_for(words)
    if course is None:
        if page in ("calendar",) or re.search(r"\b(blackboard|my courses|all courses|home)\b", words):
            key = page if page == "calendar" else ("courses" if "course" in words else "activity")
            return {"url": BASE + GLOBAL_PAGES[key], "label": f"Blackboard {key}"}
        # An item named without its course is still unique across the term.
        for c in all_courses:
            it = item_by_words(words, [i for i in items(c) if item_url(c, i)])
            if it:
                return {"url": item_url(c, it), "label": f"{c['code']}: {it['title']}"}
        return {"why": "which class? " + ", ".join(c["title"] for c in all_courses)}
    pool = [i for i in items(course) if item_url(course, i)]
    it = item_by_words(words, pool)
    if it:
        return {"url": item_url(course, it), "label": f"{course['code']}: {it['title']}"}
    if page:
        return {"url": f"{BASE}/ultra/courses/{course['id']}/{COURSE_PAGES[page]}",
                "label": f"{course['title']} {page}"}
    pick = _jev_pick(said, course, pool, ask)
    if pick:
        return pick
    return {"url": f"{BASE}/ultra/courses/{course['id']}/outline", "label": f"{course['title']} content"}


def _jev_pick(said: str, course: dict, pool: list[dict], ask) -> dict | None:
    ask = ask or (lambda s, q: jev.ask(s, q, timeout=2.0, decision="bb"))
    options = {f"p_{p}": f"the course's {p} page" for p in COURSE_PAGES}
    options.update({f"i{n}": f"the item titled \"{i['title'][:90]}\"" for n, i in enumerate(pool[:200])})
    answers = ask({"asked": said, "course": course["title"]}, {"where": {"type": "choice", "instructions": {
        "question": f"A student asked `asked` about their {course['title']} course on Blackboard. "
                    "Which page or item should open?",
        "note": "Pick the item when they name or describe one thing; a page when they want a whole area."},
        "criteria": options}}) or {}
    answer = answers.get("where") or {}
    choice, probs = answer.get("choice"), answer.get("probabilities") or {}
    if not choice:
        return None

    def target(key):
        if key.startswith("p_"):
            p = key[2:]
            return {"url": f"{BASE}/ultra/courses/{course['id']}/{COURSE_PAGES[p]}", "label": f"{course['title']} {p}"}
        i = pool[int(key[1:])]
        return {"url": item_url(course, i), "label": f"{course['code']}: {i['title']}"}

    if probs.get(choice, 0.0) >= JEV_FLOOR:
        return target(choice)
    top = sorted(probs.items(), key=lambda kv: -kv[1])[:2]
    return {"ask": [target(k)["label"] for k, _ in top]}
