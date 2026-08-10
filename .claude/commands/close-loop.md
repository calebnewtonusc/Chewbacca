---
description: End-of-session wrap-up — commit staged changes, push to GitHub, log what was done, prep for next session
allowed-tools: Bash(git:*), Bash(gh:*), Bash(date:*), Read, Edit, Write, Glob
---

# Close Loop

End-of-session workflow. Commit, push, log, set up tomorrow.

## Step 1: Check git state

```bash
git status
git diff --stat HEAD
```

Report: files modified, staged, untracked that might matter.

## Step 2: Check for .env leaks before committing

```bash
git diff --cached --name-only | grep -E "^\.env|\.env\." && echo "WARNING: .env file staged!" || echo "No .env files staged"
```

If any `.env` file is staged — STOP and unstage it immediately:

```bash
git reset HEAD .env
```

## Step 3: Commit anything uncommitted

If there are staged or unstaged changes:

1. Show the diff summary
2. Stage specific files by name — never `git add -A` or `git add .`
3. Commit with a meaningful message (no Co-Authored-By lines):

```bash
git add {specific files}
git commit -m "feat: {what was built/fixed}"
```

If changes span multiple project branches (submodules), handle each separately.

## Step 4: Push to GitHub

After committing, push:

```bash
git push origin main
```

If the remote doesn't exist yet:

```bash
GITHUB_USER=$(gh api user --jq .login 2>/dev/null)
gh repo create "$GITHUB_USER/{repo-name}" --private --source=. --push
```

Share the GitHub URL.

## Step 5: What did we accomplish?

List in plain English:

- What was built or fixed
- What files changed
- Any open TODOs or unfinished threads

## Step 6: Append to activity log

If `.claude/context/ACTIVITY_LOG.md` exists, append:

```markdown
### {YYYY-MM-DD}: {1-line session title}

- {bullet of what was done}
- {any important decisions}
- {what's left / follow-up}
```

If the file doesn't exist, create it with this entry as the first record.

## Step 7: Next session setup

State clearly:

- The 1 thing that absolutely needs to happen next session
- Any context that would be lost without noting it

Keep the whole output brief. This is a ritual, not a report.
