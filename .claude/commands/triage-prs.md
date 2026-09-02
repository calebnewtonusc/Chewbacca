---
description: Generate a prioritized PR triage dashboard, classify by module, review state, scope, and risk
allowed-tools: Bash(gh pr:*), Bash(gh api:*), Bash(gh repo:*)
argument-hint: "[repo in owner/repo format, or current repo if omitted]"
---

# PR Triage Dashboard

## Step 1: Fetch open PRs

```
gh pr list --state open --limit 100 --json number,title,author,createdAt,updatedAt,labels,reviewDecision,isDraft,additions,deletions,changedFiles,headRefName,baseRefName,mergeable
```

For each PR, fetch its file list to determine module:

```
gh pr view {number} --json files --jq '.files[].path'
```

## Step 2: Classify each PR

**Module** (based on changed file paths):

- `web/ui`: components, pages, styles
- `api`: routes, handlers, middleware
- `db/schema`: migrations, schema, ORM models
- `auth`: authentication, session, OAuth
- `ai/ml`: model integration, prompts, inference
- `infra/ci`: GitHub Actions, Vercel config, Docker
- `tests`: test files only
- `docs`: documentation only
- `deps`: dependency bumps
- `other`: doesn't fit above

**Review state:**

- `approved`: at least one approval, no changes requested
- `changes-requested`: reviewer asked for changes
- `reviewed`: comments but no formal decision
- `automated-only`: only bot reviews (Copilot, Dependabot)
- `no-review`: no reviews at all

**Scope:**

- `tiny`: <50 lines changed
- `small`: 50–200 lines
- `medium`: 200–500 lines
- `large`: 500–2000 lines
- `xl`: 2000+ lines or 15+ files

**Risk type:**

- `fix`: bug fix, safe to merge quickly after review
- `feature`: new capability, standard review
- `architectural`: changes interfaces, DB schema, auth flow, needs deep review

## Step 3: Detect conflicts/overlaps

Identify PRs that touch the same files, flag potential merge conflicts or conceptual overlap.

## Step 4: Output dashboard

```
## Summary
Total open: N | Approved: N | Needs review: N | Stale (>14d): N

## Ready to Merge (approved, CI green, no conflicts)
[table: # | title | author | scope | module | age]

## Fixes Needing Review (risk=fix, no approval)
[table: # | title | author | scope | module | age]

## Features Needing Review
[table: # | title | author | scope | module | age]

## Architectural PRs (need deep review)
[table: # | title | author | scope | module | age | what changes]

## Changes Requested: Awaiting Author
[table: # | title | author | feedback summary | stale?]

## Draft PRs
[table: # | title | author | progress note]

## Stale (>14 days no activity)
[table: # | title | author | last activity]

## Conflicts / Overlaps
[list: PR A + PR B touch same files: [file list]]

## Module Groups
[by module: list of PR numbers + titles]

## Recommendations
[3-5 concrete next actions for the team]
```

## Rules

- Read-only. No comments, approvals, or merges.
- Use only `gh` CLI.
- Do not speculate about code quality without reading the diff.
