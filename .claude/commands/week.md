---
description: The week ahead across classes, deadlines, and work, with the load honestly counted
allowed-tools: Bash(coursework:*), Bash(gh:*), Bash(date:*), Read
argument-hint: "[days, default 7]"
---

# Week

## Step 1: the fixed structure

```bash
coursework week --days ${ARGUMENTS:-7}
coursework due --days $(( ${ARGUMENTS:-7} + 7 ))
```

Classes and deadlines are fixed. Everything else negotiates around them.

## Step 2: the rest of the week

Read the personal context files for active projects and commitments. If GitHub
is wired, check what is actually assigned:

```bash
gh pr list --author "@me" --state open --limit 5
```

## Step 3: count the load honestly

Add up the hours the fixed structure already takes: class time, labs,
commuting, standing commitments. Subtract from the week. What is left is the
plannable time, and it is always less than it looks.

Then say plainly whether the week fits. If it does not, load the `life-ops`
skill and cut: what is unrecoverable if missed, what is cheap to be late on,
what can be dropped whole.

## Output

Day by day, short. Under each day: classes, then anything due, then the one
piece of real work assigned to it. End with:

- **The week's single non-negotiable.**
- **What is being deliberately dropped.** Naming it beats discovering it.
