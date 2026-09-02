---
description: Deep audit a project directory, find bugs, incomplete work, security issues, and inconsistencies
allowed-tools: Read, Glob, Grep, Bash(git log:*), Bash(npm:*), Bash(npx tsc:*)
argument-hint: "<project path, e.g. projects/mergepilot/web>"
---

# Project Audit

## Step 1: Locate the project

If `$ARGUMENTS` is given, use that path. Otherwise, use the current directory. Confirm it's a valid project by checking for `package.json`, `pyproject.toml`, or equivalent.

## Step 2: Understand the project

Read:

- `package.json` / `pyproject.toml`, dependencies, scripts, entry points
- `README.md`: stated purpose and architecture
- Top-level source files, build a mental map before diving in

Do NOT comment on what you haven't read.

## Step 3: Run compiler/type checks (read-only output)

```bash
# TypeScript
npx tsc --noEmit

# Python
python -m mypy . --ignore-missing-imports 2>&1 | head -50
```

Document all errors. Do not fix yet.

## Step 4: Scan for incomplete work

Search for:

```
TODO, FIXME, HACK, XXX, unimplemented, placeholder, stub, temporary, @ts-ignore, @ts-expect-error
```

Any `TODO`/`FIXME` in production code paths is a finding.

## Step 5: Security audit

Check for:

- SQL injection: string interpolation in queries (should use parameterized queries)
- Secrets in source: hardcoded API keys, tokens, passwords
- `eval()` / `Function()` with user-supplied input
- Missing authentication checks on sensitive routes
- `dangerouslySetInnerHTML` with unsanitized content
- PII logged at any level
- User-supplied IDs trusted without ownership verification

## Step 6: TypeScript safety

Check for:

- `as any` without an explanatory comment
- Non-null assertions (`!`) on values that could be null/undefined
- `@ts-ignore` without explanation
- External data typed as `any` instead of `unknown` + narrowed

## Step 7: Async correctness

Check for:

- `await` inside a loop when calls are independent (should be `Promise.all`)
- Fire-and-forget Promises without `.catch()`
- Mixed `async/await` and `.then()/.catch()` chains in the same function

## Step 8: Consistency review

Check for:

- Dead code (exported but never imported, unreachable branches)
- Duplicate logic across files (near-identical functions)
- Naming inconsistencies (camelCase vs snake_case for same concept)
- Env variables used but not documented in `.env.example`

## Step 9: Findings report

Group by severity:

**Critical**: will cause data loss, security breach, or crash in production
**High**: bug that breaks a feature or creates incorrect behavior
**Medium**: correctness risk, missing edge case handling
**Low**: style, naming, missing docs
**Nit**: very minor

For each finding:

```
[SEVERITY] file:line
Category: (Security | TypeScript | Async | Incomplete | Consistency)
Issue: <what's wrong>
Evidence: <exact code or pattern>
Fix: <what to do>
```

End with a summary table and total count per severity.

## Rules

- Read every file you cite before reporting a finding.
- Never report a finding without specific file:line evidence.
- Distinguish confirmed bugs from conditional risks.
- This is a read-only audit, do not implement fixes unless the user explicitly asks.
