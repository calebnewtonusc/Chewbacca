---
description: Mark a Todoist task as complete, search by name or ID
allowed-tools: Bash(curl:*), Read
argument-hint: "<task name or ID>"
---

# Done

Mark a Todoist task complete. Search by name if no ID given.

## Step 1: Find the task

If $ARGUMENTS is a number, use it as task ID directly.

Otherwise search today's tasks for a match:

```bash
curl -sf "https://api.todoist.com/rest/v2/tasks?filter=today" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN"
```

Find the task whose content fuzzy-matches $ARGUMENTS. If multiple match, ask which one.

## Step 2: Close the task

```bash
curl -sf -X POST "https://api.todoist.com/rest/v2/tasks/{task_id}/close" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN"
```

## Step 3: Confirm

Report: "Done: {task name}", one line.

If $ARGUMENTS is "all sprint 1" or similar, close all tasks in that sprint for today.
