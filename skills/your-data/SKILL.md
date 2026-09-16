---
name: your-data
description: "Decide what Chewbacca is allowed to read, then get it in. Use when somebody has just installed this and does not know where to start, asks what it can see or what it can read, asks how to get their life into it, says they want to get organised, asks which permissions it needs or why macOS is asking for something, wants to import their messages, contacts, LinkedIn, email, calendar, notes, or files, or asks what to do with a Google Drive or Takeout export. Also use when a question could not be answered because the data was never imported, and when deciding what to import next."
---

# Getting somebody's life into this

The person reading this may have never opened a terminal. They have a laptop
with fifteen years of stuff on it and no idea what is safe to hand over.

**Ask what they want to share before you take anything.** Consent first is not
politeness here: this reads message history and an address book, and somebody
who feels surprised by that will uninstall it and be right to.

## 1. Offer the menu, in their words

Say what each one gives them, not what it is technically. Let them pick any
subset, in any order, and let them say no to anything.

| Offer it like this    | It unlocks                                                       | Stays local |
| --------------------- | ---------------------------------------------------------------- | ----------- |
| "Your texts"          | who you are drifting from, and what people actually told you     | yes         |
| "Your contacts"       | names on cards instead of phone numbers, and companies filled in | yes         |
| "Your LinkedIn"       | where people work, who moved jobs, who asked to connect first    | yes         |
| "Your email"          | what you owe people, and who is waiting on you                   | yes         |
| "Your calendar"       | who you actually spend time with, versus who you mean to         | yes         |
| "Your notes"          | things you wrote down once and never found again                 | yes         |
| "Files and documents" | a place to look things up: leases, policies, records             | yes         |

**Nothing in that table leaves the machine.** Say so explicitly and without
hedging, because it is the question they are actually asking. The one exception
is a Clay key if they add one later, and that is opt-in and separate.

**Start with one.** Somebody who says yes to everything at once will spend an
hour on permissions and quit. Texts first: it is the richest, and it is the one
that makes the rest worth having.

## 2. Guide the permission, do not hand them a list

Every one of these needs macOS to grant access, and the prompts are confusing.
Say what will appear before it appears.

- **Texts and contacts** need **Full Disk Access** for the terminal. System
  Settings, Privacy and Security, Full Disk Access, add their terminal, then
  quit and reopen it. **The reopen is the part everybody misses**, and without
  it the grant silently does nothing.
- **Calendar, Reminders, Notes, Mail** each throw their own prompt the first
  time. `mac doctor` prints which are granted; exit code 2 means somebody has to
  click something, so ask rather than retrying.
- If something worked yesterday and not today, it is almost always the terminal
  being replaced by an update and losing its grant.

Run `mac doctor` and read it to them in plain language. Do not paste the table.

## 3. Then actually pull it in

In this order, because each one makes the next more useful:

```bash
people texts sync        # their whole message history
people import --mac      # the contacts app
people linkedin sync     # a LinkedIn export sitting in ~/Downloads
people linkedin locate   # where those people live, needs a Clay key, costs nothing
people distill           # turn conversations into what they know about people
```

`people` prints the next step on its own when a store is thin, so follow that
rather than reciting this list.

### The LinkedIn export

They have to request it: LinkedIn, Settings, Data Privacy, Get a copy of your
data. Pick **the larger archive**, not just connections, because the messages
and invitations files are half the value. It arrives by email in minutes to a
day. They unzip it into `~/Downloads` and that is all; the sync finds it.

Tell them to keep old exports. Two exports three months apart is a job-change
feed, and that costs nothing.

## 4. Files: zip the folders, skip the big stuff

For Google Drive, iCloud, Dropbox or a Takeout export, the goal is **a place to
look things up**, not an index of everything.

What actually helps: leases, insurance policies, tax documents, medical records,
contracts, school records, warranties, anything they would otherwise dig for.

What to leave out: video, raw photos, design files, anything over about 25MB,
and folders of software. Those cost hours of download and answer nothing.

Walk them through it:

1. In Drive, select the folders worth keeping and download them. Drive zips a
   folder automatically when you download it.
2. Make `~/life-reference/` and unzip into it, one folder per area: `housing`,
   `health`, `money`, `school`, `work`, `legal`.
3. Tell them where it is and stop. **There is nothing to import.** Any agent
   reading this skill can open and search that folder directly when a question
   needs it, which is why the structure matters more than any ingestion step.

Name files like a person would search for them. `2026-lease-signed.pdf` beats
`Scan_20260114.pdf`, and renaming twenty files is worth more than importing two
thousand.

## 5. What to say when they ask "what now"

The honest answer for somebody disorganised is that the value shows up on the
second visit, not the first. So after an import, show them one thing that was
already true and they had lost:

- `people reconnect` names somebody they have not spoken to in years
- `people show <a friend>` prints things that friend actually said
- `people who "..."` answers a question they could not have answered alone

One concrete result beats a tour of the features.

## Keeping it alive

It goes stale quietly, which is the failure mode that kills tools like this.

| When             | What                    | Why                            |
| ---------------- | ----------------------- | ------------------------------ |
| Weekly           | `people texts sync`     | picks up new conversations     |
| Weekly           | `people reconnect`      | who is slipping                |
| Monthly          | `people distill`        | new conversations become facts |
| Every few months | a fresh LinkedIn export | job changes, for free          |
| Occasionally     | `people dedupe`         | one person, two cards          |

None of it is a data-entry chore, and that is deliberate. **Never build a habit
that depends on them logging activity.** Every CRM dies that way. Last contact
is derived from messages they already sent, so it cannot go stale.

## The things to refuse

- **Do not import something they did not agree to**, even when the permission
  already happens to be granted.
- **Do not read a folder of somebody else's material** because it was in the
  same export.
- If they ask for something that is not supported yet, say so plainly. Mail,
  Calendar and Notes are readable through `mac` but are not ingested into the
  people store, and claiming otherwise produces an empty answer they will read
  as their own life being empty.
