# An honest audit, by who is holding it

Written 2026-09-21 at the end of a long night, because Caleb asked for the
truth rather than the pitch. Every number here was measured during that
session, and where something is an impression rather than a measurement it
says so.

The state in one line: Chewbacca is extraordinary for one person, promising
for five, and not yet safe to hand to a sixth.

---

## The numbers, before the opinions

```
133,422  lines tracked
  2,399  lines in setup.sh, the thing a new person runs
    105  skills installed, 39 of them written here
     52  commands in bin/
     22  hooks
    27M  .git
 PUBLIC  7 stars, 2 forks
```

---

## 1. Caleb

It works, and nobody else has anything like it.

The kit reads his calendar, texts, contacts, coursework, 652,000 words of
distilled mentors, and a relationship graph. It writes its own failures down.
It opens tabs, commits, pushes, and talks. Tonight it reorganised 450,000 files
correctly on a spoken sentence.

**The honest risk is that he is the only person it is wired for, and he cannot
see that from the inside.** Every failure found tonight had been sitting there
for days or weeks, invisible because his machine was already configured past
it. The globe key, the uninstaller, the skill router, the brain digest, the
narration: six capabilities that existed, were correct, were tested, and did
nothing.

**What he should not believe:** that the thing working on his Mac means it
works. It means it works on his Mac.

---

## 2. Gavin, and the four friends with repo access

This is the best-served group after Caleb, and the one the design actually fits.

They have Claude Max, they push to main, and the rule is "never review code, if
it breaks tell it to fix itself." For five people moving this fast that is
correct and it is producing real work: Gavin alone shipped 159 commits in four
days including the entire voice half of the HUD.

**Where it hurts them.** Two sessions in one checkout ate work three times in a
single day. The pre-commit hook now refuses mixed-session commits, and its own
advice message still points at a command that cannot clear its gate. Worktrees
solve this and nothing tells a new contributor to use one.

**And the thing they will hit next:** 105 skills, 39 written here, no owner
listed for any of them, and until tonight nothing routed to them. A sixth
person joining has no way to discover what already exists, which is how this
kit ends up with two of everything.

---

## 3. Sagar, and everyone like him

**This is the one with real evidence, and it is the most important section.**

He is the ideal sceptical user: technical enough, motivated, friendly, and he
wanted it to work. He installed it on 2026-09-20 and quit inside two hours.

> "this seems extremely dangerous to have on my computer. i don't even know how
> to remove this agent"
> "seems like malware"
> "It's not a product I need to work for me"
> "I already have clay & perplexity"
> "Adding more cognitive load is not the way"

**Every one of those is fixable and none of them was about capability.** A
browser tab reopened itself unasked, which reads as malware whatever the cause.
`uninstall.sh` existed the whole time and the closing screen never mentioned it.
That screen listed what Claude could now read, then stopped.

The closing screen now names the uninstall command and states what actually
leaves the machine. The dashboard that popped the tab is disabled before it
runs. **Neither fix has been tested on anyone.**

**What his rejection actually means:** the product's hardest problem is the
first ninety seconds. He is the proof.

---

## 4. The founder trying it today

This is the highest-stakes case and the least prepared for.

A $100M ARR founder is installing this. He will meet a 2,399-line bash script
that asks for a GitHub account, creates two repos on it, wires 22 hooks, and
installs 105 skills. If anything pops a window unasked, he is Sagar.

The trust fixes shipped last night, hours before. **Nobody has watched a
stranger run this installer end to end.** That is the single highest-value
thing anyone could do this week, and it costs one person and twenty minutes.

---

## 5. His grandma

Not close yet, and the gap is honest rather than damning.

The stated goal is "click 1 button, allow a few permissions, answer a few
questions, then boom she's iron man." Today it requires a terminal, git, a
GitHub account, an Anthropic subscription, and knowing what a hook is.

Erik Fish's question is the right one and it is now in the doctrine:

> "What of my culture am I requiring people to adopt before they are allowed to
> experience my Jesus?"

Terminal, git, GitHub, prompt engineering. Four haircuts demanded at the door.

**The voice agent is the honest path to her and it got much closer tonight**: it
now has his whole brain, the kit's doctrine, an index of all 105 skills, and it
narrates what it is doing. It still starts from a terminal.

---

## 6. A paying client, at $1-5k for setup

The product is real and the delivery is not yet.

What genuinely sells: the GTM tooling is good and was proven on live client data
tonight. `prometheus-targeting` cut 1,039,715 rows to 27,393 personalisable
humans and found two defects that would have burned the sending domains, one of
them 9,526 rows whose company name was the literal string "Person".

**What blocks a paid install today:**

- No uninstall story a buyer would accept without reading bash
- No support path when it breaks on their Mac
- Nothing versioned for them: they get main, including whatever landed at 2am
- One of the 15 MCP servers ships an invalid tool schema and fails silently

**The sellable thing right now is the GTM work, not the kit.** Do the outcome,
use the kit to do it, and sell the outcome. Selling the kit means owning
everything above for someone who has paid.

---

## 7. A stranger on GitHub

**7 stars, 2 forks, public.** That is not a criticism; nobody has been asked.

What they meet: a 298-line README, 133,000 lines, and a 2,399-line installer
that creates GitHub repos on their account. A careful engineer reads that
installer before running it, and it is long enough that most will not.

**The kit's own honesty is its best asset here**, and it is unusual. The commit
messages name the failure that caused the fix, `CREDITS.md` attributes every
borrowed skill, and `docs/THREAT-MODEL.md` exists. Very few repos this size are
this truthful about their own scars. That is worth leading with.

The blocker is trust, the same one Sagar and the founder hit.

---

## 8. Whoever maintains this in six months

This is the most under-served reader, and it may well be Caleb.

Real strengths: failures are written down as scars and memories, the commit
messages are unusually good, `doctor.sh` checks its own wiring, and the tests
encode specific incidents rather than generic coverage.

**Real debt:**

- The test suite did not finish in 400 seconds tonight. A suite nobody waits
  for is a suite nobody runs.
- `bin/hud-listen` is over 3,000 lines and does audio, streaming, drawing,
  process management, permissions and routing.
- 105 skills, no owner, no last-reviewed date. `skill-scan` grades many of
  their descriptions at 16 to 21 trigger points out of 25.
- 57 dead links sat in `docs/REFERENCE.md` because a generator emitted
  repo-root-relative paths into a file in `docs/`. Fixed, and it had been
  invisible for a long time.

---

## The pattern under all of it

Seven times in one night, the same shape: **the capability existed, was
correct, was tested, and never fired.**

Push to talk, the uninstaller, the skill router, the brain digest, the skill
index, the narration, and `do-it-yourself.md`. Not one was a missing feature.
Each one looked like a stupid model or a missing capability from outside, and
each was a wire that had come loose.

**So the highest-use work is not building. It is proving that what exists
runs.** `doctor.sh` learned this once and checks both that a hook is installed
and that something invokes it. Almost nothing else does.

---

## If only three things get done

1. **Watch one stranger install it, start to finish, and say nothing.** Every
   trust problem above is a guess until someone does this. Twenty minutes.
2. **Make the test suite finish in under two minutes.** A suite that times out
   is how the next seven silent failures ship.
3. **Decide who it is for.** Sagar said "It's not a product I need." He was
   right about himself and that is data, not rejection. The kit currently aims
   at a founder, a grandma, a PE buyer and five nineteen-year-olds at once, and
   the first ninety seconds cannot serve all four.

---

Built with Chewbacca
