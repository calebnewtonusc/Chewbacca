---
description: Generate a changelog from git log — grouped by type, since last tag or N days
allowed-tools: Bash(git:*), Read
argument-hint: "[--since=7d] [--since-tag]"
---

# Changelog

Generate a clean changelog from git history.

## Step 1: Get commits

Default: last 7 days.
If $ARGUMENTS has `--since-tag`: since last git tag.
If $ARGUMENTS has `--since=Nd`: last N days.

```bash
# Since last tag
git log $(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD~50")..HEAD --oneline

# Since N days
git log --since="7 days ago" --oneline
```

## Step 2: Parse and group

Categorize each commit by conventional commit type:

- `feat:` → Features
- `fix:` → Bug Fixes
- `chore:` / `refactor:` → Internal
- `docs:` → Documentation
- `style:` → Design / UI
- Everything else → Other

## Step 3: Output

```markdown
## Changelog: {date range}

### Features

- {feat commits, cleaned up}

### Bug Fixes

- {fix commits}

### Design / UI

- {style commits}

### Internal

- {chore/refactor commits}
```

If $ARGUMENTS has `--pr` — format for PR description instead.
