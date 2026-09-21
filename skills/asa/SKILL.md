---
name: asa
description: Answer from the A2A Spring 2026 course, 108 hours of workshops on building a business out of AI agents. Use when the user asks what the course said about something, references a week or module by number, asks how Callan or Carter taught a thing, or asks for the course's take on prompting, agent architecture, sales, marketing, operations, finance or building an AI employee. Also use when writing a new Chewbacca skill, to check whether the course already solved that problem.
---

# asa

108 hours of recorded workshops from the A2A Spring 2026 course, indexed and
searchable. 79 transcripts, 1.3 million words, published by the course as
PDFs rather than reconstructed from audio, so speaker turns are real.

## Never load a transcript

A single workshop runs 20,000 to 57,000 words. Loading one costs more than
most answers are worth and crowds out everything else in the session. Search
returns a passage and an offset; widen only the passage you need.

```bash
asa modules                                   # what exists
asa search "cold email sequence"              # ranked passages, 20 max
asa search "agent" --module week-3            # one module
asa show 09-week-3-ai-sales-department/01-workshop.md --at 48210
```

`asa` lives at `asa/bin/asa`.

## Read the notes first

`asa/notes/` holds a distilled file per module: what it teaches, the named
frameworks with their steps, the prompting patterns, the architecture, and
what is worth porting into Chewbacca. A note is a few thousand words against
a transcript's fifty thousand, so start there and go to the transcript only
when the note is thinner than the question.

`asa/INDEX.md` lists every module and session with its runtime and length.

## Module map

Weeks 0 through 12 run in order, each with a workshop, office hours and
three breakout rooms. Week 0 covers the AI architect mindset. Week 1 covers
prompts, skills and AI workspaces. Weeks 2 through 5 and 8 through 9 each
build one department: marketing, sales, operations, customer success,
leadership, finance. Week 6 builds apps and dashboards. Week 7 is the unfair
advantage. Week 10 is the business brain capstone. Week 11 covers scheduled
tasks. Bonuses cover Notion, Claude design, Claude Code, HIPAA and SEO.

## What this corpus is good for

Answering what the course actually taught, with a citation. Checking a
framework's real steps before repeating a half-remembered version. Deciding
whether a new Chewbacca skill is already solved here.

## What it is not

Not authority. The course is one group's opinion, recorded in 2026, and some
of it is dated or is a pitch for the next program. When it conflicts with the
user's own rules in `~/.claude/rules/`, his rules win. Say which source a
claim comes from rather than blending them.

The transcripts are paid material and stay on this machine. Quote a sentence
to make a point, never a passage, and never republish them.
