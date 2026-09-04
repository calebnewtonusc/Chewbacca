#!/bin/sh
# Timing, logging, a watchdog and an output cap. See lib.sh.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" 2>/dev/null || true
type hook_init >/dev/null 2>&1 && hook_init kit-route.sh 5
# Route a prompt into an existing kit, at the moment the person types it.
#
# The session briefing lists what kits exist, but a list read once at session
# start competes with everything else in context by the time it matters. This
# fires on the actual prompt, says nothing at all unless there is a real match,
# and when there is one it names the kit and the path.
#
# Silence is the common case and it costs nothing.

# The payload arrives on stdin, and the heredoc below also claims stdin, so it
# has to be read first and handed over out of band. Without this the script runs
# fine and silently never matches anything, because sys.stdin is the script.
KIT_ROUTE_PAYLOAD=$(cat)
export KIT_ROUTE_PAYLOAD

exec python3 <<'PY'
import json, os, re, subprocess, sys

try:
    payload = json.loads(os.environ.get("KIT_ROUTE_PAYLOAD") or "{}")
except Exception:
    raise SystemExit(0)

prompt = (payload.get("prompt") or "").strip()
# Too short to match on, or already a slash command the user chose deliberately.
if len(prompt) < 12 or prompt.startswith("/"):
    raise SystemExit(0)

# Do not re-route somebody who is already standing in a kit.
cwd = payload.get("cwd") or os.getcwd()
try:
    d = cwd
    for _ in range(4):
        if os.path.exists(os.path.join(d, ".kit")):
            raise SystemExit(0)
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
except Exception:
    pass

def kit_paths():
    for candidate in (
        os.path.expanduser("~/.local/bin/kits"),
        os.path.expanduser("~/.claude/bin/kits"),
        "kits",
    ):
        try:
            out = subprocess.run([candidate, "--paths"], capture_output=True,
                                 text=True, timeout=5)
        except (FileNotFoundError, OSError):
            continue
        if out.returncode == 0:
            return [p for p in out.stdout.split("\n") if p.strip()]
        return []
    return []

STOP = {
    "a","an","and","the","or","for","to","of","in","on","at","my","me","i","is",
    "it","that","this","with","about","from","was","were","be","been","have",
    "has","had","do","does","did","not","no","any","some","them","they","their",
    "something","anything","someone","somebody","need","needs","want","help",
    "get","getting","one","what","when","where","how","why","who","which",
}

def stems(text):
    """Crude 5-character stemming. Good enough that apply, applying and
    application collapse together, which is the whole reason this exists:
    somebody types "apply to three clubs" and the marker says "applying"."""
    out = set()
    for w in re.findall(r"[a-z][a-z0-9'-]+", text.lower()):
        if w in STOP or len(w) < 3:
            continue
        out.add(w[:5])
    return out

def stem_seq(text):
    """Content-word stems in order, so adjacency can be checked. Stopwords are
    dropped from both sides, which makes "a specific role" and "specific role"
    the same sequence."""
    out = []
    for w in re.findall(r"[a-z][a-z0-9'-]+", text.lower()):
        if w in STOP or len(w) < 3:
            continue
        out.append(w[:5])
    return out

def bigrams(seq):
    return {(seq[i], seq[i + 1]) for i in range(len(seq) - 1)}

prompt_stems = stems(prompt)
prompt_bigrams = bigrams(stem_seq(prompt))

def read_kit(d):
    marker = os.path.join(d, ".kit")
    try:
        with open(marker) as fh:
            raw = fh.read()
    except OSError:
        return None

    def field(name):
        m = re.search(rf"^{name}:\s*(.+)$", raw, re.M)
        return m.group(1).strip() if m else ""

    if field("status") == "template":
        return None
    name = field("name")
    use_when = field("use-when")
    if not name or "{{" in name or not use_when or "{{" in use_when:
        return None
    kit_stems = (stems(use_when) | stems(field("domain"))) - stems(name.replace("-", " "))
    return {"dir": d, "name": name, "use_when": use_when, "stems": kit_stems}

loaded = [k for k in (read_kit(d) for d in kit_paths()) if k]

# How many kits claim each stem. A stem claimed by exactly one kit is a strong
# signal on its own; a stem several kits share, like "letter", is nearly noise.
claims = {}
for k in loaded:
    for st in k["stems"]:
        claims[st] = claims.get(st, 0) + 1

best = None
for k in loaded:
    d, name, use_when, kit_stems = k["dir"], k["name"], k["use_when"], k["stems"]
    hits = prompt_stems & kit_stems

    # Loose word overlap is not enough. "write a cover for this book about
    # letters from a soldier" hits both "cover" and "letter" and has nothing to
    # do with applying anywhere. A phrase appearing intact is the real signal,
    # so require either an adjacent two-word match plus one more hit, or three
    # separate hits with no phrase at all.
    kit_bigrams = set()
    for phrase in use_when.split(","):
        kit_bigrams |= bigrams(stem_seq(phrase))
    phrase_hit = bool(prompt_bigrams & kit_bigrams)

    # Two words that belong to this kit and no other is as good as a phrase.
    # "apply" and "essay" only ever point one direction; "letter" does not.
    distinctive = {h for h in hits if claims.get(h, 0) == 1}

    strong = (
        (phrase_hit and len(hits) >= 2)
        or len(distinctive) >= 2
        or len(hits) >= 3
    )
    if not strong:
        continue

    score = len(hits) + len(distinctive) * 2 + (10 if phrase_hit else 0)
    if best is None or score > best[0]:
        best = (score, name, d, sorted(hits))

if not best:
    raise SystemExit(0)

_, name, path, _hits = best
short = path.replace(os.path.expanduser("~"), "~")

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": (
            f"This request matches an existing kit: {name} at {short}. "
            f"cd there and work inside it. It already holds this person's state, "
            f"facts and deadlines, and its CLAUDE.md decides what happens next. "
            f"Answering here instead throws that away and produces advice that is "
            f"gone when the window closes. If on reading it the kit clearly does "
            f"not fit, say so in one line and carry on."
        ),
    }
}))
PY
