---
description: Run the full quality gate (typecheck, lint, tests) before shipping any change
allowed-tools: Bash(npm:*), Bash(npx:*), Bash(python:*), Bash(pytest:*), Bash(git:*)
---

Run the quality gate for the project at `$ARGUMENTS` (defaults to current directory).

## Step 0: .env Leak Check

Before anything else, check that no secrets are staged:

```bash
git diff --cached --name-only | grep -E "^\.env|\.env\." && echo "BLOCKED: .env file staged, unstage before shipping" || echo "Clean"
```

If a `.env` file is staged: **STOP**. Unstage it, warn the user, do not proceed.

Also scan staged content for obvious secret patterns:

```bash
git diff --cached | grep -E "(sk-ant|sk-|ANTHROPIC|API_KEY|SECRET|PASSWORD|TOKEN)" | grep "^+" | grep -v "example\|placeholder\|your_key\|process\.env\." | head -10
```

If real secrets appear in the diff: STOP and flag them.

## Step 1: Detect project type

- `package.json` exists → Node/TypeScript project
- `requirements.txt` / `pyproject.toml` exists → Python project
- Both → run both

## Step 2: TypeScript / Node

```bash
# Typecheck
npm run typecheck 2>/dev/null || npx tsc --noEmit

# Lint
npm run lint 2>/dev/null || npx eslint . --max-warnings 0

# Tests (if they exist)
npm test 2>/dev/null || echo "No test script found"
```

Zero errors required on typecheck and lint. All tests must pass.

## Step 3: Python

```bash
# Type checking
python -m mypy . 2>/dev/null || echo "mypy not configured"

# Tests
python -m pytest -v 2>/dev/null || echo "No pytest found"
```

## Step 4: Bundle size check (Next.js)

```bash
npm run build 2>&1 | tail -30
```

Flag any route over **150KB** first load JS. Anything over **250KB** is a hard block.

## Step 5: Summary

Report results for all steps:

```
TYPECHECK: PASS / FAIL ({error count})
LINT:      PASS / FAIL ({error count})
TESTS:     PASS / FAIL / SKIP ({pass}/{fail}/{skip})
BUNDLE:    PASS / WARN (largest route: Xkb)
ENV LEAK:  CLEAN / BLOCKED
```

If any step fails, list the specific errors and suggest fixes. Do NOT mark as shipped past a failing gate.

Clean ship = all green. Then proceed to `/push` or `/deploy`.
