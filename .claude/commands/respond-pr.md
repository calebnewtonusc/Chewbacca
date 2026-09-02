---
description: Read all review comments on a PR, triage each one, then implement fixes and reply
allowed-tools: Read, Edit, Write, Glob, Grep, Bash(gh pr:*), Bash(gh api:*), Bash(git:*), Bash(npm:*), Bash(npx tsc:*)
argument-hint: "[PR number], defaults to current branch's PR"
---

# Respond to PR Review Comments

## Step 1: Find the PR

If `$ARGUMENTS` is provided, use that as the PR number. Otherwise detect via:

```
gh pr list --head $(git branch --show-current) --json number,title,url --jq '.[0]'
```

If no PR found, stop and tell the user.

## Step 2: Fetch all review comments

Resolve repo:

```
gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"'
```

Fetch review comments (line-level):

```
gh api --paginate repos/{owner}/{repo}/pulls/{number}/comments
```

Fetch review summaries (approval state, body):

```
gh api --paginate repos/{owner}/{repo}/pulls/{number}/reviews
```

Deduplicate, bots sometimes post the same finding under multiple IDs. Group by the actual issue raised, not by comment ID.

## Step 3: Triage and plan

For each unique issue:

1. **Check if already fixed**: read the current file at the referenced location. If a prior commit resolved it, mark "already resolved".
2. **Assess validity**: is this a real problem or a false positive? Be honest. Explain false positives.
3. **Classify severity**: Critical (security/data loss) | High (bug/broken behavior) | Medium (correctness/robustness) | Low (style/nit)
4. **Plan the fix**: describe the specific code change needed.

Present a plan table to the user:

| #   | Issue | File:Line | Severity | Status | Planned Fix |
| --- | ----- | --------- | -------- | ------ | ----------- |

**Wait for user confirmation before implementing.**

## Step 4: Implement fixes

After confirmation:

1. Implement each fix.
2. Run the quality gate:
   - `npm run typecheck 2>/dev/null || npx tsc --noEmit` (if TypeScript changed)
   - `npm run lint 2>/dev/null || npx eslint . --max-warnings 0` (if available)
   - `npm test` (if tests affected)
3. Commit with a message referencing the review.
4. Push to the branch.

## Step 5: Reply to comments

For each addressed comment, reply on the PR with what was fixed and the commit SHA. For false positives or already-resolved items, explain why no change was needed.

## Rules

- Never assess code you haven't read. Always read the referenced file and line first.
- Group duplicate findings (same issue from multiple bots), reply to all of them.
- Do not make changes beyond what the review comments ask for.
- If you disagree with a comment, surface it during the planning phase rather than ignoring it.
- Follow project conventions: no `as any`, no non-null assertions without comment, parameterized queries only.
