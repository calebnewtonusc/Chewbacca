# Mega prompt: close the gap between the HUD demo and an ambient agent

Written 2026-09-20. Paste the block below into a fresh Chewbacca tab.

Context for whoever reads this later: a live HUD demo ran on 2026-09-20 (five
panels over the whole screen, real data, a ticker repainting every 2s off load
average and frontmost app). Caleb's response was that it is "so far from Iron
Man." This prompt sends the next session after the actual gap, which is that
everything in the kit is pull and nothing is push.

Two findings from this session that the prompt depends on:

- 19 launchd agents already run, including `com.calebnewton.people-sync`,
  `people-dashboard`, `claude-contacts-export`, `linkedin-clay-sync`,
  `com.claude.mac-endpoint`, `com.claude.telegram-relay`, `ai.nova.brief`.
  The ambient scheduling layer exists and nothing is wired to the HUD.
- `~/.claude/skills/speaking/SKILL.md` is Peter Steinberger's skill, hardcoded
  to `/Users/steipete/Projects/`. It sits in Caleb's kit pointing at another
  person's repos. There may be more like it.

---

```
Read this whole thing before you touch anything. Do the phases in order.
Do not start writing code in Phase 1.

## THE JOB

Chewbacca is my Claude Code kit. Today it did a live HUD demo: five panels
floating over my screen, real data, a ticker repainting every 2 seconds off
load average and frontmost app.

What I want is closer to JARVIS. Your job is NOT to make the panels prettier.
Your job is to figure out what the real distance is between what I have and
an ambient agent that is genuinely present, then give me a staged plan to
close it, then ship the first stage.

My working diagnosis, which you should attack rather than accept:
everything in the kit is PULL. I type, it acts, it stops. It is blind between
turns, it never speaks first, it never notices anything, and the glass is
write-only, whereas JARVIS is push, which is where I think the whole distance
lives. Prove me right or prove me wrong with evidence from the actual machine.

## PHASE 0: INVENTORY WHAT EXISTS (do not skip, do not guess)

Do not rediscover these. They were verified today, 2026-09-20:

- 106 skills in ~/.claude/skills, 30 of them in the chewbacca repo
- 57 slash commands, 12 MCP servers, 19 hooks in settings.json, 4 subagents
- 19 launchd agents in ~/Library/LaunchAgents, INCLUDING ones I already own:
  com.calebnewton.people-sync, people-dashboard, claude-contacts-export,
  linkedin-clay-sync, com.claude.mac-endpoint, com.claude.telegram-relay,
  ai.nova.brief
- hud CLI at ~/.local/bin/hud, Bob Lines protocol, running on ~/.bob/hud.sock
- hud supports: draw, listen, clear, close, screen marks (m), Button/Field/
  Select/Checkbox components that send actions back up the socket
- people.db: 3,349 people, 9,675 observations, 3,937 interactions, 237MB
- chat.db: 632,390 messages total, 255,133 sent by me
- ~/second-brain: 4,072 markdown files, 1.46M words, 1,039 commits
- 140 git repos under ~/Desktop/2026-Code
- chewbacca repo: 217,827 lines, 421 commits
- coursework CLI with a live syllabus ledger
- skills that already sense: watch-skill (live screen watching), peekaboo,
  mac-see, mac-brief, mac-followups, texts, obsidian

Now go verify the parts that matter to the plan and answer these in writing:

1. Which of those 19 launchd agents actually fire, how often, and what do they
   do with their output? Read the plists and the logs. I suspect several write
   to a file nobody ever reads. Name the dead ones.
2. Does anything on this machine currently CALL Claude without me typing?
   mac-endpoint and telegram-relay sound like they might. Trace them.
3. Is there any voice path, in or out? TTS, STT, dictation, a wake word.
   Check what is installed, not what could be installed.
4. Does anything ever listen on the hud socket? Grep the whole kit for
   `hud listen` and for Button action handlers. My guess is zero. Confirm.
5. AUDIT FOR FOREIGN SKILLS. ~/.claude/skills/speaking/SKILL.md is Peter
   Steinberger's, hardcoded to /Users/steipete/Projects/. It is sitting in my
   kit pointing at another person's repos. Sweep every skill for hardcoded
   paths that are not mine, for other people's names, and for anything that
   would break or leak on a fresh install. List every one you find.

Write Phase 0 findings to a file before moving on. If a number here turns out
to be wrong, correct it and say so.

## PHASE 1: RESEARCH THE CRAFT (before any architecture)

My global rules require researching a genre before producing in it. This genre
is ambient and agentic interfaces. Do not design from vibes and do not design
from the Iron Man movies.

Find and actually read, preferring sources on this machine first (summarize
for pages, yt-transcript for video, never WebFetch a YouTube URL):

- Mark Weiser and calm technology. The original ubicomp writing and the
  "calm technology" principles. This is the canonical prior art for a display
  that lives at the edge of attention and it is 30 years old.
- The literature on why assistants fail in practice: interruption cost,
  attention residue, alert fatigue, trust calibration, the cost asymmetry
  between a false positive and a false negative in a proactive system.
- Notification design from people who ship it. What earns an interruption.
- Voice interface design. Specifically when voice is worse than a glance,
  because I suspect a talking agent is the wrong instinct and I want that
  tested rather than assumed.
- Agent UX: how shipped agentic products handle initiative, confirmation,
  undo, and showing their reasoning. Find teardowns, not marketing.
- The actual JARVIS scenes. What is he doing that is real interaction design
  versus what is a movie affordance that cannot exist. Separate the two
  explicitly, in a table.

Extract RULES, not vibes. "Interrupt only when the cost of not knowing now
exceeds the cost of breaking focus" is a rule. "Feel magical" is nothing.
Aim for 10 to 20 rules with a source next to each.

Write these to a craft doc in the repo. The kit already has crafts/ with
interface.md in it. Read that first, extend it rather than duplicating it.

## PHASE 2: THE HONEST GAP ANALYSIS

With Phase 0 and Phase 1 in hand, tell me the truth about the distance. I want
the diagnosis structured as:

- What I already have that I am not using. I expect this to be the biggest
  bucket and the cheapest wins. The launchd agents and hud listen are my
  candidates.
- What is genuinely missing and has to be built.
- What I think I want but the research says is a bad idea. Push back here.
  If the literature says a proactive voice agent is mostly regretted, say so
  and say it plainly, do not soften it.
- What is impossible or not worth it on a Mac in 2026, and why.

Rank everything by (impact on it feeling present) divided by (effort). Show
the ranking. I want to see the math, not just the conclusion.

## PHASE 3: ARCHITECTURE

Design the thing. Constraints:

- It must work when no Claude Code tab is open. An agent that only exists
  inside my terminal session is the thing I am trying to escape.
- It must be able to initiate. Define exactly what earns an interruption and
  what does not, grounded in the Phase 1 rules, not in your taste.
- It must be able to act and then report, not only display.
- The glass must be bidirectional. Button and Field already exist, so what is
  missing is a process on the other end of the socket that listens for them.
- It has to degrade safely. Define what happens when the model is slow, the
  socket is dead, a sensor lies, or it is simply wrong. A confidently wrong
  ambient agent is worse than no agent, and I will turn it off after two bad
  interrupts. Design for that failure explicitly.
- Privacy: chat.db and people.db are the most sensitive things on this
  machine. Be specific about what leaves it and what does not. Do not write
  "nothing uploads" unless you verified it, because that claim has been wrong
  in this kit before.

Draw the architecture. Use the hud Diagram component to show it to me on the
glass, not just in markdown.

## PHASE 4: STAGED ROADMAP

Stages, each independently shippable, each with a demo I can run and a way to
turn it off. Stage 1 must be completable today and must be the single highest
ranked item from Phase 2, not the most fun one.

For each stage: what it does, what it costs me in attention, how I kill it,
and what would make me revert it.

## PHASE 5: EVALS

How do we know it worked. Not vibes. Propose measurable things: how often it
interrupted, how often I acted on the interrupt versus dismissed it, how often
it was wrong, time from a real event to me knowing about it. A proactive
system with no dismissal-rate metric is a system that will annoy me into
uninstalling it.

Put these in skills/<name>/evals/evals.json per the kit convention.

## THEN BUILD STAGE 1

Ship it. Verify it running with a screenshot or a log, not with an exit code.
Report what actually works and what does not.

## DELIVERABLE

A git repo, pushed to GitHub, not a Claude Artifact. Structure it so an agent
can consume it: CLAUDE.md, AGENTS.md, skills/<name>/SKILL.md with
evals/evals.json, the craft doc, the Phase 0 audit, the Phase 2 gap analysis,
the roadmap. Tell me the URL.

## ANTI-GOALS

- Do not make the existing panels prettier. That is not the gap.
- Do not add a feature because JARVIS had it. Every capability needs a reason
  from Phase 1 or Phase 2.
- Do not build a scheduler. I have launchd and 19 agents already running.
- Do not ask me for approval between phases. Act and report. Ask only if a
  fact would change the design and it is not on disk, and keep working on
  everything else while you wait.
- Do not put an unverified number in anything. Use a [NEED:] marker.
```

---

## Two things to watch in the next session

Phase 0 question 5 (the foreign-skill audit) is the one most likely to find
something embarrassing. Phase 2's "what you think you want but shouldn't have"
is the one most likely to get quietly skipped. Push back if either is thin.
