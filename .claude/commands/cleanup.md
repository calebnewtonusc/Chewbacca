---
description: Find and remove dead code, unused imports, console.logs, and TODO comments
allowed-tools: Bash(grep:*), Bash(find:*), Bash(npx:*), Read, Glob, Edit
argument-hint: "[project-path]"
---

# Cleanup

Find and optionally fix dead code in the project.

## Step 1: Find unused imports

```bash
npx ts-unused-exports tsconfig.json 2>/dev/null | head -20
```

## Step 2: Find console.logs in non-test files

```bash
grep -rn "console\.log\|console\.warn\|console\.error" --include="*.ts" --include="*.tsx" . 2>/dev/null | grep -v "\.test\.\|\.spec\.\|logger\." | head -20
```

## Step 3: Find TODO/FIXME/HACK comments

```bash
grep -rn "TODO\|FIXME\|HACK\|XXX\|TEMP\|REMOVE" --include="*.ts" --include="*.tsx" --include="*.py" . 2>/dev/null | grep -v "node_modules\|\.next"
```

## Step 4: Find dead files (no imports)

```bash
# Files that are never imported by anything else
npx depcheck 2>/dev/null | grep "Unused files" -A 20
```

## Step 5: Find commented-out code blocks

```bash
grep -rn "^//\s*[a-zA-Z]" --include="*.ts" --include="*.tsx" . 2>/dev/null | grep -v "eslint\|prettier\|@ts-" | head -20
```

## Step 6: Report and fix

List everything found. Then ask: "Fix all of these, or just report?"

If fixing:

- Remove console.logs (unless they're part of a logger pattern)
- Remove commented-out code blocks older than the current feature
- Leave TODO comments but list them for the user to decide
- Never auto-delete files, list them and ask
