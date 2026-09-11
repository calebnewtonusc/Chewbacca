#!/usr/bin/env python3
"""Which slash commands have no natural-language path.

The rule this enforces: nobody using this kit should ever HAVE to type a slash
command. A command is a shortcut for someone who already knows the kit. If the
only way to get a behavior is to know its command name, then the behavior is
invisible to the person the kit is actually for, who will type "what's due" and
never "/due".

So every command needs a skill that covers the same ground. This reports the
ones that do not.

WHAT THIS NUMBER IS WORTH, stated up front because the first version of this
tool was wrong and nearly shipped anyway.

It compares word sets: the command's description against skill descriptions, and
the command's body against skill bodies. Word overlap is not firing. The first
cut used two hard thresholds and called everything below them an ORPHAN, which
flagged /week as uncovered even though life-ops shares 55% of its body, and
scored /push against avoid-ai-writing at 0.64 on words like "commit" and
"message". Tuning those thresholds until the output matched what I already
believed would have been fitting the number to the guess.

So it reports a gradient, not a verdict. A low score means LOOK HERE, never
"this is uncovered". The only thing that proves a skill fires on a sentence is
running the sentence, which is what the behavioral eval is for.

  python3 tools/commands.py           weakest coverage first
  python3 tools/commands.py --all     every command
  python3 tools/commands.py --json
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
STOP = {
    "the", "a", "an", "and", "or", "of", "to", "in", "for", "on", "with", "what",
    "is", "it", "that", "this", "from", "by", "at", "as", "be", "are", "was",
    "run", "then", "if", "not", "no", "all", "any", "one", "two", "three", "get",
    "use", "using", "into", "out", "up", "down", "each", "every", "you", "your",
    "its", "has", "have", "will", "can", "does", "do", "done", "new", "next",
    "first", "last", "full", "same", "own", "just", "only", "also", "how", "why",
    "when", "where", "which", "who", "make", "made", "than", "them", "they",
}


def terms(text, floor=4):
    return {w for w in re.findall(r"[a-z][a-z-]{%d,}" % (floor - 1), text.lower())
            if w not in STOP}


def frontmatter(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        return {}, text
    meta = {}
    for line in m.group(1).split("\n"):
        if ": " in line and not line.startswith((" ", "\t")):
            k, _, v = line.partition(": ")
            meta[k.strip()] = v.strip().strip("\"'")
    return meta, m.group(2)


def skills():
    out = {}
    for root in (REPO / "skills", Path.home() / ".claude" / "skills"):
        for p in sorted(root.glob("*/SKILL.md")):
            name = p.parent.name
            if name in out:
                continue
            meta, body = frontmatter(p)
            out[name] = {
                "desc_terms": terms(meta.get("description", "")),
                "body": body.lower(),
                "body_terms": terms(body),
            }
    return out


def covering(cmd_name, meta, body, sk):
    """Rank every skill by how much of this command's ground it covers.

    Two signals, weighted unequally on purpose. Description overlap is the
    scarcer, more meaningful signal: it is the text Claude actually reads when
    choosing a skill, and command descriptions are short enough that a match
    means something. Body overlap is abundant and noisy, since any two markdown
    files about software share a lot of words, so it counts for less."""
    want_desc = terms(meta.get("description", ""))
    want_body = terms(body)
    hits = []
    for name, s in sk.items():
        if name == cmd_name or name.replace("-", "") == cmd_name.replace("-", ""):
            hits.append((name, 1.0))
            continue
        d = len(want_desc & s["desc_terms"]) / max(len(want_desc), 1)
        # Jaccard on bodies, not intersection-over-command. Dividing by the
        # command's size alone rewards a skill for being LARGE: avoid-ai-writing
        # has a huge body, so it came up as the closest match for eight
        # unrelated commands including /deploy and /todo. Union in the
        # denominator prices that in.
        b = len(want_body & s["body_terms"]) / max(len(want_body | s["body_terms"]), 1)
        score = round(0.7 * d + 0.3 * b, 2)
        if score > 0:
            hits.append((name, score))
    return sorted(hits, key=lambda h: -h[1])


def main():
    sk = skills()
    rows = []
    for path in sorted((REPO / ".claude" / "commands").glob("*.md")):
        meta, body = frontmatter(path)
        name = path.stem
        hits = covering(name, meta, body, sk)
        best = hits[0] if hits else ("none", 0.0)
        rows.append({
            "command": name,
            "description": meta.get("description", ""),
            "best_skill": best[0],
            "score": best[1],
            "runners_up": [h[0] for h in hits[1:3]],
        })

    if "--json" in sys.argv:
        print(json.dumps(rows, indent=2))
        return 0

    rows.sort(key=lambda r: r["score"])
    show = rows if "--all" in sys.argv else rows[:20]

    for r in show:
        band = "weak  " if r["score"] < 0.20 else ("thin  " if r["score"] < 0.35 else "ok    ")
        print(f"  {band}{r['score']:<5} /{r['command']:<16} closest: {r['best_skill']}")
        if r["score"] < 0.20:
            print(f"               {r['description'][:76]}")

    weak = [r for r in rows if r["score"] < 0.20]
    print(f"\n{len(weak)} of {len(rows)} commands have no skill sharing much of their language.")
    print("That is a pointer, not a verdict. Confirm by saying the thing out loud")
    print("to a session and seeing whether anything fires.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
