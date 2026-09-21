#!/bin/sh
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init skill-route.sh 5
# Name the skill that already covers this request, at the moment it is typed.
#
# THE FAILURE THIS EXISTS FOR, 2026-09-21. Caleb: "Chewbacca's resourcefulness
# and use of agents is so retarded didn't we build a whole graph engineering
# knowledge base bruh". He was right. A session had just hand-written two
# subagent prompts with no verifier and no stop rule, and had run GROUP BY over
# a million-row people-and-orgs file, while skills/graph-engineering sat in the
# repo holding both: a task-graph reference whose first rule is that the
# verification node is non-negotiable, and a nine-stage pipeline whose stage 8
# is the exact deduplication problem the client had called hard.
#
# Thirty-two skills were installed. Zero were named. kit-route.sh routes to
# KITS and was never registered either, so nothing on the machine ever pointed
# at a skill when work started.
#
# Every SKILL.md already carries a description written to be routed on:
# skill-scan spends 25 of its 100 points on "will the description route to this
# skill at all". The descriptions were fine. Nothing read them.
#
# Same contract as kit-route.sh: deterministic, model-free, silent unless there
# is a real match. Silence is the common case and costs nothing. A router that
# speaks on every prompt is one that gets tuned out inside a week, which is the
# failure it exists to prevent.

SKILL_ROUTE_PAYLOAD=$(cat)
export SKILL_ROUTE_PAYLOAD

exec python3 <<'PY'
import json, os, re, sys

try:
    payload = json.loads(os.environ.get("SKILL_ROUTE_PAYLOAD") or "{}")
except Exception:
    raise SystemExit(0)

prompt = (payload.get("prompt") or "").strip()
# Too short to match on, or a slash command the person already chose.
if len(prompt) < 12 or prompt.startswith("/"):
    raise SystemExit(0)

# Machine traffic is not a request. On its first live firing, 2026-09-21, this
# routed a background-task completion notice to skill-creator. A notification
# is prose about the tooling, so it is full of words like test, run and file,
# and it will match something almost every time. Nobody asked it anything.
NOISE = ("SYSTEM NOTIFICATION", "task-notification", "<task-id>",
         "exited with code", "hookSpecificOutput", "task notification")
if any(marker in prompt for marker in NOISE):
    raise SystemExit(0)

ROOTS = [os.path.expanduser("~/.claude/skills")]
here = payload.get("cwd") or os.getcwd()
d = here
for _ in range(5):
    cand = os.path.join(d, "skills")
    if os.path.isdir(cand):
        ROOTS.append(cand)
        break
    parent = os.path.dirname(d)
    if parent == d:
        break
    d = parent

STOP = {
    "a","an","and","the","or","for","to","of","in","on","at","my","me","i","is",
    "it","that","this","with","about","from","was","were","be","been","have",
    "has","had","do","does","did","not","no","any","some","them","they","their",
    "something","anything","someone","somebody","need","needs","want","help",
    "get","getting","one","what","when","where","how","why","who","which","use",
    "using","user","make","made","build","see","also","its","you","your","are",
    "can","could","should","would","will","just","like","more","most","than",
    "into","over","out","up","down","then","there","here","other","same","new",
}

def stems(text):
    """Crude 5-character stemming, same as kit-route. Collapses extract,
    extraction and extracting, which is the whole point: a description says
    "extract entities" and the person types "extracting people"."""
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

# Words that are common in any description of software work and therefore say
# nothing about WHICH skill. Rarity weighting alone cannot catch these: across
# 104 installed skills, `test` and `users` are each claimed by exactly one, so
# they score as maximally distinctive while carrying no routing information.
# That pair alone put a task-completion notice into skill-creator.
#
# A match needs at least one hit from outside this set. Generic words can still
# add weight, they just cannot carry a route on their own.
GENERIC = {
    "test", "tests", "run", "runs", "file", "files", "code", "work", "data",
    "user", "users", "time", "take", "never", "refer", "scrip", "him",
    "proje", "conte", "outpu", "input", "comma", "scrip", "tool", "tools",
    "task", "tasks", "check", "add", "creat", "updat", "chang", "resul",
    "syste", "proce", "sessi", "promp", "agent", "claud",
}

def frontmatter(path):
    """name and description out of the YAML head, without a yaml dependency.
    The description is often multi-line and quoted, so this joins continuation
    lines until the next top-level key."""
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

skills = []
seen = set()
for root in ROOTS:
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

if not skills:
    raise SystemExit(0)

prompt_stems = stems(prompt)
prompt_bigrams = bigrams(stem_seq(prompt))

# A stem claimed by many skills carries no routing information. "mac" appears
# in nine of them here and picks nothing.
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
    distinctive = {h for h in hits if claims.get(h, 0) == 1}

    # Rarity weighting, not a distinctive/not-distinctive flag. Tuned against
    # 12 real prompts on 2026-09-21.
    #
    # Counting only stems claimed by exactly one skill made overlapping skills
    # cancel each other out: "why is my build failing with a null pointer
    # error" hits `error` and `faili`, both claimed by debugging AND mac-debug,
    # so neither was distinctive and the router said nothing at all. Two
    # skills claiming a stem is strong evidence. Nine claiming it is none.
    #
    # So each hit is worth 1/k where k is how many skills claim it, and the
    # floor is 0.8. A single stem nobody else uses clears it alone; two stems
    # shared with one other skill clear it together; four stems that everything
    # claims do not, which is the case that used to produce noise.
    # Two hits minimum, always. One rare stem clearing the floor by itself is
    # how "why is my build failing with a null pointer error" routed to the
    # demo skill: 5-character stemming turns `pointer` into `point`, which only
    # demo's description uses, so it scored 1.0 off a single word that had
    # nothing to do with the request. A lone stem is a coincidence; two is a
    # topic.
    #
    # 0.7 rather than 0.8: the live skill set under ~/.claude/skills is larger
    # than the repo's, so every stem is claimed more often and the same match
    # scores lower there than in a repo-only test.
    weight = sum(1.0 / claims.get(h, 1) for h in hits)
    specific = hits - GENERIC
    strong = (
        len(hits) >= 2
        and specific
        and (weight >= 0.7 or phrase_hit)
    )
    if not strong:
        continue
    score = weight * 10 + (10 if phrase_hit else 0)
    why = sorted(hits, key=lambda h: claims.get(h, 1))[:4]
    best.append((score, name, path, why))

if not best:
    raise SystemExit(0)

best.sort(reverse=True)
top = best[:2]

lines = []
for score, name, path, why in top:
    short = path.replace(os.path.expanduser("~"), "~")
    because = ", ".join(why) if why else "topic overlap"
    lines.append(f"  {name}  ({short})  matched on: {because}")

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": (
            "A skill in this kit already covers this request. Read it before "
            "deciding an approach, because it holds the failures that were "
            "already paid for:\n"
            + "\n".join(lines)
            + "\nLoad it with the Skill tool. If on reading it the skill "
              "clearly does not fit, say so in one line and carry on."
        ),
    }
}))
PY
