---
description: Compare .env.example vs .env, find missing vars, find undocumented vars
allowed-tools: Bash(cat:*), Bash(grep:*), Bash(diff:*), Read, Glob
argument-hint: "[project-path]"
---

# Env Check

Audit environment variable coverage.

## Step 1: Read both files

```bash
cat .env.example 2>/dev/null || echo "No .env.example found"
```

Do NOT read .env directly, just check which keys exist:

```bash
grep -o "^[A-Z_]*=" .env 2>/dev/null | sort
grep -o "^[A-Z_]*=" .env.example 2>/dev/null | sort
```

## Step 2: Diff

Find:

- Variables in .env.example but NOT in .env (missing, app might break)
- Variables in .env but NOT in .env.example (undocumented, security risk)

## Step 3: Check code usage

```bash
# Which env vars does the code actually reference?
grep -r "process\.env\.\|env\." --include="*.ts" --include="*.tsx" --include="*.js" . 2>/dev/null | grep -o "process\.env\.[A-Z_]*\|env\.[A-Z_]*" | sort | uniq
```

## Step 4: Report

```
MISSING FROM .env (in example but not set):
- VAR_NAME, {what it's for based on .env.example comment}

UNDOCUMENTED (in .env but not in .env.example):
- VAR_NAME, add to .env.example with a placeholder

REFERENCED IN CODE BUT NOT IN EITHER FILE:
- VAR_NAME, add to both files

ALL GOOD: {if nothing to report}
```
