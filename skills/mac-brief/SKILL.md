---
name: mac-brief
description: Generate the morning operator brief - triage the user's email, texts, and calendar into what is urgent, what needs a reply, and a suggested order for the day. Use when the user asks for their brief, their morning rundown, what they need to handle today, what is urgent, or who is waiting on them. Runs on a schedule at 8am via launchd.
---

# The operator brief

Turn a morning's raw state into a short, honest rundown of what actually needs the
user, in his voice.

## 1. Gather

```bash
chewie brief --json
```

Returns three reliable sources:
- **calendar**: today's events, from the Calendar DB directly (layer 1, fast)
- **texts**: threads where someone spoke last and is waiting, decoded from chat.db
- **email**: recent inbox, newest first, with unread flags (bounded AppleScript)

If a source reports `available: false`, say so in the brief rather than inventing.

## 2. Triage (the part that matters)

The gather is dumb on purpose. The judgment is here, and it has to be strict.

| Urgent | Noise |
|--------|-------|
| A direct question from a real person | Newsletters, receipts, automated mail |
| A deadline today | Marketing, "no reply" senders |
| Someone visibly waiting on a reply | Reactions, closed threads ("ok", "haha") |
| A time-boxed request ("free at 2?") | Anything you would not act on |

Cross-reference sources: an email and a text from the same person about the same
thing is one item. Match names across the calendar too ("call with Chen" + a text
from Chen about rescheduling = one item, flagged).

## 3. Write it

Short. His voice. No preamble, no "Good morning! Here is your brief." Just:

- **Today**: events, with conflicts called out explicitly
- **Needs a reply**: most time-sensitive first, who and what, one line each
- **Deadlines**: anything with a hard date
- **First two hours**: a suggested order, not a lecture

## 4. Deliver

Default is to print it. If he has asked for it as a text, use a confirm-gated
`send_text` to himself. **Never send anything to other people from the brief.**

## The discipline

A brief listing 40 things is one he stops reading, and then the whole feature is
dead. Twelve real items beat forty padded ones. If nothing is genuinely urgent,
the correct brief is three lines saying so. Under-reporting a fake obligation is
better than manufacturing one.
