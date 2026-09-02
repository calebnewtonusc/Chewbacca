---
description: Morning briefing: Todoist tasks for today, GitHub PRs/issues needing attention, and a focused plan for the day
allowed-tools: Bash(gh:*), Bash(curl:*), Bash(date:*), Bash(cat:*), Bash(ls:*), Read
---

# Daily Brief

Assemble the morning briefing. Pull live data, synthesize a focused daily plan. Signal over noise.

## Step 1: Today's date

```bash
date '+%A, %B %-d, %Y'
```

## Step 2: Todoist: today's tasks + overdue

```bash
# Today's tasks
curl -sf "https://api.todoist.com/rest/v2/tasks?filter=today" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN"

# Overdue tasks
curl -sf "https://api.todoist.com/rest/v2/tasks?filter=overdue" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN"
```

Group by sprint label (Sprint 1-5). Priority order within each sprint (P1 first). Count total tasks.

## Step 3: GitHub: PRs and issues

```bash
gh pr list --author "@me" --state open --json number,title,updatedAt,reviewDecision --limit 10
gh issue list --assignee "@me" --state open --json number,title,updatedAt --limit 10
```

## Step 4: Current context

Read your personal context files (`{name}-context/NOW.md`) for active projects and recent decisions. If the second brain is set up, these files load automatically at session start.

## Step 5: Synthesize the brief

```
{Day}, {Date}

TOP PRIORITIES (3 max)
1. {most critical, with why}
2. {second}
3. {third}

SPRINT PLAN
Sprint 1 ({n}): {tasks}
Sprint 2 ({n}): {tasks}
Sprint 3 ({n}): {tasks}
Sprint 4 ({n}): {tasks}
Sprint 5 ({n}): {tasks}

OVERDUE ({n}): {task names, if any}

GITHUB
{PRs/issues needing action}

FOCUS BLOCK
{Best 2-hour deep work window + what to do in it, based on current context}
```

Under 400 words. No fluff.

## After the Brief

Ask: "Want me to reorder tasks, adjust sprints, or kick off anything specific?"
