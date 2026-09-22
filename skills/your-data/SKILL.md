---
name: your-data
description: "Decide what Chewbacca is allowed to read, then get it in. Use when somebody has just installed this and does not know where to start, asks what it can see or read, asks how to get their life into it, asks which permissions it needs or why macOS is prompting, wants to import messages, contacts, LinkedIn, email, calendar, notes or files, or asks what to do with a Google Drive or Takeout export. Also use when a question could not be answered because the data was never imported, and when deciding what to import next."
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

Offer only sources relevant to the person's goal: selected texts, contacts,
calendar entries, notes, email, files or a LinkedIn export. They can use Chewbacca
without importing any of these.

Read `docs/PRIVACY.md` before describing a data flow. A local database does not
mean local-only processing: content placed in a hosted agent's context goes to
that provider. `people distill` sends selected message content through its model
backend; connected APIs and MCP services receive their tool inputs. Explain the
actual destination before enabling a new source or external enrichment step.

Start with the smallest useful source they choose. Do not default to their whole
message history, and do not treat agreement to one source as agreement to others.

## 2. Guide the permission, do not hand them a list

Every one of these needs macOS to grant access, and the prompts are confusing.
Say what will appear before it appears.

- **Texts and contacts** need **Full Disk Access** for the app actually executing the read (for example the editor, Codex, or terminal). System
  Settings, Privacy and Security, Full Disk Access, add that host app, then
  quit and reopen it. **The reopen is the part everybody misses**, and without
  it the grant silently does nothing.
- **Calendar, Reminders, Notes, Mail** each throw their own prompt the first
  time. `mac doctor` prints which are granted; exit code 2 means somebody has to
  click something, so ask rather than retrying.
- If something worked yesterday and not today, it is almost always the terminal
  being replaced by an update and losing its grant.

Run `mac doctor` and read it to them in plain language. Do not paste the table.

## 3. Then actually pull it in

Run only commands corresponding to the sources and processing the person has
authorized. These are separate actions, not an automatic sequence:

```sh
people texts sync        # imports message history; broad scope, explain first
people import --mac      # imports Contacts
people linkedin sync     # imports the chosen LinkedIn export
people linkedin locate   # external enrichment; requires separate service access
people distill           # model processing of message content, potentially paid
```

Inspect the command's current help for scoping and preview options. If it cannot
limit the import to what they authorized, stop and explain that limit. Do not run
a broader import merely because it is the only command available. Pricing and
provider retention depend on their accounts; never promise either is free.

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
