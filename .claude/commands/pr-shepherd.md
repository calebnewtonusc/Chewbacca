---
description: Full PR lifecycle, review, fix findings, address comments, quality gate, push, CI fix loop, merge
allowed-tools: Bash(gh pr *), Bash(gh api *), Bash(gh repo view:*), Bash(gh run *), Bash(git *), Bash(npm:*), Bash(npx:*), Read, Edit, Write, Grep, Glob, Agent
argument-hint: "<pr-number or url> [--fix] [--merge] [--review-only]"
---

# PR Shepherd

Full PR lifecycle: review → fix → quality gate → push → CI → merge.

Parse `$ARGUMENTS`:

- Extract PR number from bare number or `https://github.com/owner/repo/pull/123`
- Flags: `--fix` (auto-fix without asking), `--merge` (merge when CI green), `--review-only` (stop after review)
- If no PR: `gh pr list --head $(git branch --show-current) --json number --jq '.[0].number'`

---

## Phase 1: Situational Awareness

Gather in parallel:

```
gh pr view {number} --json number,title,body,author,baseRefName,headRefName,headRefOid,state,isDraft,mergeable,mergeStateStatus,files,additions,deletions,labels
gh pr diff {number}
gh pr diff {number} --name-only
gh pr checks {number} --json name,status,conclusion
gh api --paginate repos/{owner}/{repo}/pulls/{number}/comments
gh api --paginate repos/{owner}/{repo}/pulls/{number}/reviews
```

Print status card:

```
PR #{number}: {title}
Author: {author}    Base: {base} ← {head}
Size: +{additions} -{deletions} across {file_count} files
CI: {PASS|FAIL|PENDING|NONE}    Mergeable: {yes|no|conflict}
Unresolved comments: {N}    Draft: {yes|no}
```

Decide mode:

- Unresolved review comments → Phase 2a
- No reviews yet → Phase 2b (deep review)
- CI failing only → Phase 4
- All green + approved → Phase 6 (merge ready)

---

## Phase 2a: Address Existing Review Comments

For each unresolved comment:

1. Read the referenced code at file:line
2. Classify: ✅ valid & unresolved / ✅ already fixed / ❌ false positive / 🔧 nit
3. Deduplicate (bots often duplicate)

| # | Source | File:Line | Issue | Status | Planned Fix |

Wait for confirmation (unless `--fix`), then Phase 3.

---

## Phase 2b: Deep Review (6 Lenses)

Read EVERY changed file in full. Prioritize: service logic > handlers > types > tests > docs.

### Correctness

Off-by-one, wrong operators, inverted conditions, unreachable code, type confusion, error propagation, TOCTOU races.

### Edge cases & failure handling

Empty/null/undefined, external service failures, integer boundaries, malformed input, partial failures.

### Security

Auth/authz bypass, IDOR, injection (SQL/command/log), data leakage in logs/errors, resource exhaustion, replay attacks.

### Test coverage

New public functions tested? Error paths? Edge cases? Existing tests still valid?

### Architecture

Follows patterns? Unnecessary abstractions? Duplicated logic? Clean boundaries?

**Findings table:**

| # | Severity | Category | File:Line | Finding | Suggested Fix |

Severity: Critical > High > Medium > Low > Nit

---

## Phase 3: Fix

Check out PR branch: `gh pr checkout {number}`

Implement fixes. After all fixes, run quality gate:

```bash
npm run typecheck 2>/dev/null || npx tsc --noEmit
npm run lint 2>/dev/null || npx eslint . --max-warnings 0
npm test
```

If any step fails: fix and re-run. Loop up to 3 times. Stop and report if still failing.

---

## Phase 4: Commit & Push

Stage by file name (never `git add -A`):

```bash
git add path/to/file1 path/to/file2
git commit -m "fix: address review findings on PR #{number}"
git push origin {headRefName}
```

Reply to addressed review comments on GitHub with commit SHA and description.

---

## Phase 5: CI Monitor

Poll (don't use `--watch`):

```
gh pr checks {number} --json name,status,conclusion
```

Re-check every 30s, up to 10 minutes.

If CI fails (up to 3 attempts):

1. `gh run view {run_id} --log-failed`
2. Diagnose, fix, re-run quality gate, push
3. Go back to top of Phase 5

---

## Phase 6: Merge

Print final status. If `--merge` or user confirms and all conditions met (CI pass, no CHANGES_REQUESTED, not draft, no conflicts):

```
gh pr merge {number} --{squash|rebase|merge} --delete-branch
```

---

## Rules

- Read before judging. No comments without reading the code.
- Fix the pattern, not just the instance, grep for similar bugs across the codebase.
- Don't over-fix. Only change what was flagged.
- Distinguish certainty: "this IS a bug" vs "this COULD be a bug if X".
