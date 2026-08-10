---
description: Fetch a GitHub issue, create a branch, research the codebase, plan the fix, implement with tests, and commit
allowed-tools: Bash(gh issue view:*), Bash(gh repo view:*), Bash(git fetch:*), Bash(git checkout:*), Bash(git status:*), Bash(git branch:*), Bash(git add:*), Bash(git commit:*), Bash(npm:*), Bash(npx:*), Read, Edit, Write, Grep, Glob
argument-hint: "<issue-number or github-issue-url>"
---

# Fix GitHub Issue

## Step 1: Resolve the issue

Parse `$ARGUMENTS`:

- URL like `https://github.com/owner/repo/issues/42` → extract `42`
- Bare number → use directly
- Empty → stop and ask

Fetch the issue:

```
gh issue view {number} --json title,body,labels,assignees,comments,state
```

If closed, warn and ask whether to proceed.

## Step 2: Create a branch

1. `git fetch origin`
2. `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`
3. `git checkout -b fix/{number}-{short-slug} origin/{default-branch}`
   - slug: 3–5 words from the issue title, lowercase, hyphenated

If uncommitted changes exist, warn and stop.

## Step 3: Understand the issue

Summarize in 2–3 sentences:

- What's broken / missing
- What "done" looks like (acceptance criteria)
- Any constraints (compat, performance)

List open questions if the issue is ambiguous.

## Step 4: Research the codebase

1. Find relevant files, functions, and types mentioned in the issue. Read them in full.
2. Trace the code path from entry point (route, CLI, event handler) to relevant logic.
3. Find existing tests for the affected code.
4. Look for similar patterns to maintain consistency.

## Step 5: Enter planning mode

Plan MUST cover:

1. **Root cause** (bugs) or **design approach** (features)
2. **Files to modify** with specific descriptions
3. **New files** (if any) with justification
4. **Tests to add**: happy path, error paths, edge cases
5. **Migration/compatibility concerns**

Wait for approval before implementing.

## Step 6: Implement

1. Make each change from the plan.
2. Write all planned tests.
3. Run the quality gate:
   - `npm run typecheck 2>/dev/null || npx tsc --noEmit`: zero errors
   - `npm run lint 2>/dev/null || npx eslint . --max-warnings 0`: zero errors
   - `npm test`: all pass
4. Fix any failures before proceeding.

## Step 7: Commit and summarize

Commit message: `fix: {short description} (#{number})`

Summarize:

- Files changed with line references
- Tests added and what they cover
- Any follow-up work or open questions
