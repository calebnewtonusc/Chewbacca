---
description: Show today's Todoist sprint breakdown — tasks by sprint, priorities, estimated load
allowed-tools: Bash(curl:*), Bash(date:*), Read
---

# Sprint

Pull today's Todoist tasks and show a clean sprint-by-sprint breakdown.

## Step 1: Pull today's tasks

```bash
curl -sf "https://api.todoist.com/rest/v2/tasks?filter=today" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN"
```

Also pull overdue:

```bash
curl -sf "https://api.todoist.com/rest/v2/tasks?filter=overdue" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN"
```

## Step 2: Parse and organize

Sprint system. This is a default shape, not a law. Rename these to match how
you actually label tasks, or delete the buckets you do not use:

- Sprint 1: Morning admin and anything urgent
- Sprint 2: Main focus block, the hardest thing of the day
- Sprint 3: Secondary focus
- Sprint 4: Everything else that must move today
- Sprint 5: Evening wrap-up, calls, admin

Priority sort within each sprint: P1 (api=4) first, P4 (api=1) last.

## Step 3: Output

```
TODAY — {Day}, {Date}
{total} tasks across {n} sprints

SPRINT 1 — Morning Admin ({n} tasks)
  [P1] {task}
  [P3] {task}

SPRINT 2 — Deep Work ({n} tasks)
  ...

OVERDUE ({n})
  {tasks that should have been done}

LOAD ASSESSMENT
{Light / Moderate / Heavy} — {brief reasoning}
```

If $ARGUMENTS is "reorder" — suggest optimal reordering based on time of day and dependencies.
