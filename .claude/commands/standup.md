---
description: Generate a daily standup, what was done, what's next, any blockers
allowed-tools: Bash(git:*), Bash(gh:*), Bash(curl:*), Bash(date:*), Read
---

# Standup

Generate a daily standup update. Pull real data, be specific.

## Step 1: Yesterday's git activity

```bash
git log --since="24 hours ago" --author="$(git config user.email)" --oneline --all 2>/dev/null | head -20
```

Also check sibling project directories for recent commits:

```bash
PARENT_DIR="$(dirname "$(pwd)")"
for dir in "$PARENT_DIR"/*/; do
  [ -d "$dir/.git" ] || continue
  COMMITS=$(cd "$dir" && git log --since="24 hours ago" --oneline 2>/dev/null | head -5)
  [ -n "$COMMITS" ] && echo "$(basename "$dir"):" && echo "$COMMITS"
done 2>/dev/null
```

## Step 2: Todoist tasks (if configured)

```bash
if [ -n "$TODOIST_API_TOKEN" ]; then
  curl -sf "https://api.todoist.com/rest/v2/tasks?filter=today" \
    -H "Authorization: Bearer $TODOIST_API_TOKEN" 2>/dev/null
else
  echo "TODOIST_API_TOKEN not set. Add it to ~/.claude/settings.json env block."
fi
```

## Step 3: Any open PRs or blockers

```bash
gh pr list --author "@me" --state open --json number,title,reviewDecision --limit 5
```

## Step 4: Generate standup

Output in this format (concise, no fluff):

```
YESTERDAY
- {what was actually shipped/done, specific commits or tasks}

TODAY
- {top 3 things from sprint plan}

BLOCKERS
- {anything stuck, or "None"}
```

Under 150 words. Specific and factual.
