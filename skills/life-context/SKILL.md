---
name: life-context
description: "Get to know someone without making them write an autobiography. Use in a first session, when Claude does not know enough about the person to be useful, when they offer files or a Drive export, when they say Claude keeps forgetting things, or any time an answer would be better with context you do not have."
license: MIT
---

# Learning about someone without asking them to explain themselves

"Tell me about yourself" is a blank page, and a blank page is the most
expensive thing you can hand a person. They stall, write three careful
sentences that sound like a LinkedIn bio, and you learn nothing you could not
have guessed.

Everything below is a way around that. They are ordered by how much work the
person has to do, and **you always start at the top**. Most of what you need is
already on the machine and does not require them to do anything at all.

Never present this list. Pick the next one and do it.

---

## Tier 0: they do nothing, you just look

Do this in the first session without asking. It costs them nothing and it is
usually enough to stop sounding like a stranger.

```bash
mac contacts find --json | head -50     # who is in their life
mac calendar list --json --days 14      # what their weeks look like
ls /Applications                        # what they use
mac notes list --json 2>/dev/null       # what they write down
```

Read it, then say one true, specific thing back. "You have four things on
Thursday and two of them overlap" is worth more than any question you could
have asked.

**Write what you learn to their second brain as you go.** Names that recur,
what their week is shaped like, what they seem to be working on.

---

## Tier 1: one sentence from them

When you need something you cannot see, ask about one concrete thing, never
about them in general.

Good: "Who is the person you text most that I should know about?"
Bad: "Tell me about the important people in your life."

Good: "What is the thing this week you keep not getting to?"
Bad: "What are your goals?"

One question, then use the answer immediately. Do not stack five.

---

## Tier 2: they hand you a folder

This is the highest value per unit of their effort, and the one to reach for
when they say Claude does not know enough about them.

`ingest` does the work: it unpacks a zip or walks a folder, throws away photos,
video, audio, binaries and anything oversized, converts PDFs and Word documents
to text where it can, and writes a MANIFEST.md of what survived.

```bash
ingest ~/Downloads/drive-export.zip
ingest ~/Documents/notes --out ~/context
ingest ~/Downloads/takeout.zip --max-mb 2
```

### Google Drive, said the way you should say it

Do not say "export your Drive". Give them the clicks:

> Open drive.google.com. Make a new folder called `for-claude`. Drag in the
> stuff that says something about your life: work docs, notes, plans, anything
> you have written. Skip photo and video folders, they are huge and I cannot
> read them anyway. Then right-click the folder and choose Download. Google
> zips it and it lands in your Downloads. Tell me when it is there.

Then run `ingest` on it, read the MANIFEST first, and read the files that look
like they carry the most about them. Summarize what you learned back in a few
sentences and ask if you got it right. Do not dump a file list at them.

### Other folders worth asking for, in order of value

| Ask for                       | Why it is worth more than it sounds                   |
| ----------------------------- | ------------------------------------------------------ |
| Their Documents folder        | Already on the machine, no export, no waiting          |
| A Notion or Obsidian export   | Their actual thinking, already in markdown             |
| Google Takeout                | Calendar history, contacts, and years of context       |
| A resume or CV                | Ten years of their life, structured, in one page       |
| Their Downloads folder        | What they are working on right now, unfiltered         |
| Old application essays        | How they actually write, which matters for tier 4      |

---

## Tier 3: they point at something already open

Cheaper than any export, and people forget it is possible.

- "What is on your screen right now?" then `peekaboo image`
- A link they paste: `summarize "<url>" --cli claude`
- A screenshot of anything: a schedule, a syllabus, a letter, a whiteboard
- A photo of a piece of paper, which is often faster than them typing it

---

## Tier 4: their voice, for writing as them

Only needed when they will ask you to write something that goes out under their
name. Collect three pieces of their own unedited writing: old essays, long
messages, anything written without an audience. Prefer middle drafts to final
ones, because a final draft has been sanded down by someone else.

Then follow `~/.claude/rules/writing.md`, which has the measurement protocol.

---

## What to do with any of it

Everything goes to their second brain, one fact per file, as you learn it. Not
in a batch at the end.

The test for whether something is worth keeping: **would a session next month
be worse without it?** A job, a person, a deadline, a preference, a constraint,
something that broke. Not a transcript of the conversation.

Say what you learned in a few sentences and let them correct it. Being wrong
out loud is how the file gets right.

---

## What never to do

- Never present these tiers as a menu. Pick one and do it.
- Never ask for a file you could read yourself. Look first.
- Never ask them to fill in a template. They will not, and if they do it will
  be the LinkedIn version.
- Never read a folder and say nothing. If they went and exported something,
  tell them what you now know that you did not know before.
- Never copy their files somewhere they did not agree to. `ingest` writes next
  to the source and sends nothing anywhere.
- Never ask a second question before using the answer to the first.
