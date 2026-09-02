---
description: Update CURRENT_CONTEXT with what's happening right now, major decisions, shifts, new projects
allowed-tools: Read, Edit, Write, Bash(date:*)
argument-hint: "<what changed or what's happening now>"
---

# Context Update

Update your personal context files with what's happening right now.

> **Requires**: Second brain set up via `setup.sh`. Files live in `{name}-context/`.

## Step 1: Read current context

Find and read your `NOW.md` file from your personal context repo. Check `$HOME/dev/{name}-context/NOW.md` or the path configured during setup.

## Step 2: Parse the update

$ARGUMENTS describes what changed. Determine:

- Is this a new decision? Add to "Recent Decisions"
- Is this a new project? Add to "Active Projects"
- Is this a priority shift? Update "Current Priorities"
- Is this about current work or commitments? Update NOW.md
- Is this a new key insight? Add note to relevant section

## Step 3: Update the file

Use Edit to add/update the relevant section. Always update:

- `Last Updated:` date at the top and bottom
- `Next update:` date

## Step 4: Confirm

Report what section was updated and what was added. One paragraph, then done.
