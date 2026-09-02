---
description: Add a Todoist task from natural language, auto-assigns sprint, priority, due date
allowed-tools: Bash(curl:*), Bash(date:*), Read
argument-hint: "<task description> [due:today|tomorrow|monday] [sprint:1-5] [p1|p2|p3|p4]"
---

# Todo

Add a task to Todoist from natural language. Parse $ARGUMENTS to extract task details.

## Step 1: Parse the request

Extract from $ARGUMENTS:

- **Content**: the task description
- **Due date**: look for "today", "tomorrow", day names, or "due:X"
- **Sprint**: look for "sprint 1-5" or "s1-s5", default to Sprint 3
- **Priority**: look for "p1/p2/p3/p4" or "urgent/important", default to P3

Priority mapping (Todoist API):

- P1 = priority 4 (highest)
- P2 = priority 3
- P3 = priority 2
- P4 = priority 1 (default)

## Step 2: Get label IDs for sprint

```bash
curl -sf "https://api.todoist.com/rest/v2/labels" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN"
```

Find the label ID for "Sprint {n}".

## Step 3: Create the task

```bash
curl -sf -X POST "https://api.todoist.com/rest/v2/tasks" \
  -H "Authorization: Bearer $TODOIST_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "{content}",
    "due_string": "{due}",
    "priority": {priority_api_value},
    "labels": ["{sprint_label}"]
  }'
```

## Step 4: Confirm

Report: task name, sprint, priority, due date. One line, no fluff.
