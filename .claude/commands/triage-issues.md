---
description: Triage GitHub issues, classify, score severity/opportunity, detect duplicates, output a prioritized report
allowed-tools: Bash(gh issue:*), Bash(gh api:*), Bash(gh repo:*)
argument-hint: "[repo in owner/repo format, or current repo if omitted]"
---

# Issue Triage

## Step 1: Fetch issues

If `$ARGUMENTS` specifies a repo, use it. Otherwise use the current repo:

```
gh issue list --state open --limit 100 --json number,title,body,labels,createdAt,updatedAt,assignees,comments
```

For large repos, paginate:

```
gh api --paginate repos/{owner}/{repo}/issues?state=open&per_page=100
```

## Step 2: Classify each issue

**Type:**

- `bug`: broken existing functionality with clear reproduction
- `feature`: new capability requested
- `ambiguous`: unclear whether bug or feature, or needs more info

**Spec quality:**

- `well-specified`: clear steps, expected vs actual, acceptance criteria
- `adequate`: enough to act on, minor gaps
- `under-specified`: missing key information to reproduce or implement

## Step 3: Score bugs by severity

```
severity = impact(1-4) × urgency(1-3) × scope(1-3)
```

- +5 bonus if security-related
- +3 bonus if a PR already exists

**Impact:** 4=data loss/security, 3=core feature broken, 2=degraded experience, 1=cosmetic
**Urgency:** 3=blocking users now, 2=workaround exists, 1=edge case
**Scope:** 3=all users, 2=some users, 1=rare scenario

## Step 4: Score features by opportunity

```
opportunity = value(1-4) + (4 - effort(1-3)) + readiness(1-3)
```

- +2 bonus if multiple users requested
- +2 bonus if aligns with active roadmap work

## Step 5: Detect relationships

- Duplicates (same root cause, different reporters)
- Clusters (related issues that could be tackled together)
- Already fixed (check recent commits/PRs for the symptom)
- Blockers (issue A blocks issue B)
- Epic candidates (5+ related issues that form a theme)

## Step 6: Output triage report

```
## Critical Bugs (score ≥ 24)
[table: number | title | score | spec quality | note]

## High-Opportunity Features (score ≥ 8)
[table: number | title | score | spec quality | note]

## Under-Specified (needs clarification)
[list: number | title | what's missing]

## Duplicates
[list: kept | duplicates | reason]

## Stale (>90 days, no activity)
[list: number | title | age]

## By Area
[grouped by label or topic]

## Recommendations
[3-5 concrete next actions]
```

## Rules

- Read-only. No comments, labels, or closes.
- Use only `gh` CLI, no web scraping.
- Don't speculate about fixes. Triage is assessment only.
