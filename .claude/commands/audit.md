---
description: Security and code quality audit, find vulnerabilities, bad patterns, and tech debt
allowed-tools: Bash(git:*), Bash(npm:*), Bash(npx:*), Bash(grep:*), Bash(find:*), Read, Glob
argument-hint: "[project-path]"
---

# Audit

Deep audit of the project at $ARGUMENTS (or current directory). No shortcuts.

## Step 1: Security scan

```bash
# Check for secrets in code
# The kit's own scanner, which matches on position rather than on three known
# prefixes. The prefix list here missed a live Todoist token for 149 days
# because that token is forty bare hex characters.
secret-scan . 2>/dev/null || python3 bin/secret-scan .

# Check .gitignore covers .env files
cat .gitignore 2>/dev/null | grep "\.env"

# Find any hardcoded localhost URLs that might ship to prod
grep -r "localhost:3000\|localhost:8000\|127\.0\.0\.1" --include="*.ts" --include="*.tsx" . 2>/dev/null | grep -v "\.test\." | grep -v "comment"
```

## Step 2: Dependency audit

```bash
npm audit --audit-level=moderate 2>/dev/null || pnpm audit 2>/dev/null
npx depcheck 2>/dev/null | head -30
```

## Step 3: Code quality patterns

```bash
# Unhandled promises
grep -r "\.then(" --include="*.ts" --include="*.tsx" . 2>/dev/null | grep -v "catch" | head -10

# Any-typed variables
grep -r ": any" --include="*.ts" --include="*.tsx" . 2>/dev/null | grep -v "// " | head -10

# Console.logs left in (non-test files)
grep -r "console\.log" --include="*.ts" --include="*.tsx" . 2>/dev/null | grep -v "\.test\." | grep -v "logger" | head -10

# TODO/FIXME count
# Every language in the tree, not three. This grepped .ts, .tsx and .py in
# repos that are mostly bash, Swift, or Go, and reported zero every time.
grep -rIn "TODO\|FIXME\|HACK\|XXX" . 2>/dev/null \
  | grep -vE "node_modules|\.git/|\.build/|DerivedData|dist/|vendor/"
```

## Step 4: Design quality (for UI projects)

Check for:

- Raw `<button>` without Tailwind classes
- Missing hover states (`hover:` classes)
- Inline styles (`style={{`)
- Hard-coded pixel widths
- Missing `cursor-pointer` on clickable elements

```bash
grep -r "style={{" --include="*.tsx" . 2>/dev/null | grep -v "navbar\|transform\|opacity\|transition" | head -10
grep -r "<button" --include="*.tsx" . 2>/dev/null | grep -v "className" | head -5
```

## Step 5: Report

Grade each category (A/B/C/D/F) and list specific issues with file:line references. Be specific, not just "found issues" but "file.tsx:42 has an unhandled promise".

Prioritize by severity: Security > Correctness > Quality > Style.
