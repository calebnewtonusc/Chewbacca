#!/usr/bin/env python3
"""Name the skill that covers a request, deterministically and with no model.

The voice agent (`hud-listen` lean profile) runs Bash-only with no skills
loaded, because loading all ~105 skill descriptions costs 80k tokens a turn.
That is why the voice was weaker than chat: it could not reach the skill
library at all. This is the router that closes the gap. The voice calls it with
the request, gets back the one skill that fits, reads that SKILL.md, and follows
it, paying for one skill body instead of a hundred descriptions.

    python3 tools/skill_match.py "who do I know at Stripe"
    echo "what is due this week" | python3 tools/skill_match.py

Prints the best one or two matches as `name<TAB>path<TAB>why`, best first, and
prints nothing when nothing matches, which is the common and correct case.

The matching (stemming, rarity weighting, the generic-word floor) is the same
logic `.claude/hooks/skill-route.sh` runs for chat sessions, tuned against real
prompts on 2026-09-21. This is a faithful extraction so the voice routes exactly
as chat does. The hook still carries its own copy; folding the hook onto this
module is the follow-up, kept separate here to avoid editing a live hook while
several sessions are active.
"""

import os
import re
import sys

STOP = {
    "a", "an", "and", "the", "or", "for", "to", "of", "in", "on", "at", "my",
    "me", "i", "is", "it", "that", "this", "with", "about", "from", "was",
    "were", "be", "been", "have", "has", "had", "do", "does", "did", "not",
    "no", "any", "some", "them", "they", "their", "something", "anything",
    "someone", "somebody", "need", "needs", "want", "help", "get", "getting",
    "one", "what", "when", "where", "how", "why", "who", "which", "use",
    "using", "user", "make", "made", "build", "see", "also", "its", "you",
    "your", "are", "can", "could", "should", "would", "will", "just", "like",
    "more", "most", "than", "into", "over", "out", "up", "down", "then",
    "there", "here", "other", "same", "new",
}

# Words common to any description of software work, so they say nothing about
# WHICH skill. A match needs at least one hit from outside this set.
GENERIC = {
    "test", "tests", "run", "runs", "file", "files", "code", "work", "data",
    "user", "users", "time", "take", "never", "refer", "scrip", "him",
    "proje", "conte", "outpu", "input", "comma", "tool", "tools", "task",
    "tasks", "check", "add", "creat", "updat", "chang", "resul", "syste",
    "proce", "sessi", "promp", "agent", "claud",
}


def stems(text):
    out = set()
    for w in re.findall(r"[a-z][a-z0-9'-]+", text.lower()):
        if w in STOP or len(w) < 3:
            continue
        out.add(w[:5])
    return out


def stem_seq(text):
    out = []
    for w in re.findall(r"[a-z][a-z0-9'-]+", text.lower()):
        if w in STOP or len(w) < 3:
            continue
        out.append(w[:5])
    return out


def bigrams(seq):
    return {(seq[i], seq[i + 1]) for i in range(len(seq) - 1)}


def frontmatter(path):
    """name and description out of the YAML head, without a yaml dependency."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read(8000)
    except OSError:
        return None, None
    if not text.startswith("---"):
        return None, None
    head = text.split("---", 2)
    if len(head) < 3:
        return None, None
    body = head[1]
    name = desc = None
    key = None
    for line in body.split("\n"):
        m = re.match(r"^([a-zA-Z_-]+):\s*(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2)
            if key == "name":
                name = val.strip().strip("'\"")
            elif key == "description":
                desc = val.strip().strip("'\"")
            continue
        if key == "description" and line.strip():
            desc = (desc or "") + " " + line.strip().strip("'\"")
    return name, desc


def skill_roots(cwd=None):
    roots = [
        os.path.join(os.path.expanduser(
            os.environ.get("CHEWBACCA_HOME", "~/.chewbacca")), "skills"),
        os.path.expanduser("~/.claude/skills"),
        os.path.expanduser("~/.agents/skills"),
    ]
    if os.environ.get("CHEWBACCA_SKILLS_DIR"):
        roots.append(os.environ["CHEWBACCA_SKILLS_DIR"])
    d = cwd or os.getcwd()
    for _ in range(5):
        cand = os.path.join(d, "skills")
        if os.path.isdir(cand):
            roots.append(cand)
            break
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return roots


def load_skills(cwd=None):
    skills = []
    seen = set()
    for root in skill_roots(cwd):
        if not os.path.isdir(root):
            continue
        for entry in sorted(os.listdir(root)):
            sk = os.path.join(root, entry, "SKILL.md")
            if not os.path.isfile(sk) or entry in seen:
                continue
            name, desc = frontmatter(sk)
            if not name or not desc:
                continue
            seen.add(entry)
            skills.append((name, desc, sk))
    return skills


def match(prompt, cwd=None):
    """Return up to two (name, path, why) tuples, best first, or []."""
    prompt = (prompt or "").strip()
    if len(prompt) < 12 or prompt.startswith("/"):
        return []

    skills = load_skills(cwd)
    if not skills:
        return []

    prompt_stems = stems(prompt)
    prompt_bigrams = bigrams(stem_seq(prompt))

    claims = {}
    for _n, desc, _p in skills:
        for s in stems(desc):
            claims[s] = claims.get(s, 0) + 1

    best = []
    for name, desc, path in skills:
        d_stems = stems(desc)
        hits = prompt_stems & d_stems
        if not hits:
            continue
        phrase_hit = bool(prompt_bigrams & bigrams(stem_seq(desc)))
        weight = sum(1.0 / claims.get(h, 1) for h in hits)
        specific = hits - GENERIC
        strong = len(hits) >= 2 and specific and (weight >= 0.7 or phrase_hit)
        if not strong:
            continue
        score = weight * 10 + (10 if phrase_hit else 0)
        why = sorted(hits, key=lambda h: claims.get(h, 1))[:4]
        best.append((score, name, path, why))

    if not best:
        return []
    best.sort(reverse=True)
    out = []
    for _score, name, path, why in best[:2]:
        short = path.replace(os.path.expanduser("~"), "~")
        out.append((name, short, ", ".join(why) if why else "topic overlap"))
    return out


def main():
    args = [a for a in sys.argv[1:] if a != "-"]
    prompt = " ".join(args) if args else sys.stdin.read()
    for name, path, why in match(prompt):
        print(f"{name}\t{path}\t{why}")


if __name__ == "__main__":
    main()
