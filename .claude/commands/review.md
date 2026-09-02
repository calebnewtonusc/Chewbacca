---
description: Thorough code review, security, performance, accessibility, TypeScript, error states
allowed-tools: Bash(npm:*), Bash(npx:*), Bash(grep:*), Bash(ls:*), Read, Glob
argument-hint: "[file path or directory, defaults to recent changes]"
---

# Review

Deep review of `$ARGUMENTS` (or `git diff HEAD~1` if no argument given). Look for real problems, not style preferences.

## Step 1: Get the code under review

If `$ARGUMENTS` is a file path, read it.
If `$ARGUMENTS` is empty, get recent changes:

```bash
git diff HEAD~1 --name-only
git diff HEAD~1
```

## Step 2: Security scan

Check every one of these:

**SQL injection / NoSQL injection**

- All user input goes through parameterized queries or Supabase `.eq()` / `.filter()`, never string interpolation
- No `${}` inside raw SQL strings

**Secrets**

- No hardcoded API keys, tokens, passwords
- All secrets via `process.env.VAR_NAME`
- `.env` files not imported or referenced in source

**Auth / Authorization**

- Every protected route checks `auth.getUser()` or equivalent
- User-supplied IDs verified against `auth.uid()`, never trusted blindly
- No `select *` returning data that could belong to another user

**XSS**

- `dangerouslySetInnerHTML` only with DOMPurify sanitization
- No `eval()` or `new Function()` with user content

**Input validation**

- Every API route body Zod-validated
- External data typed as `unknown`, narrowed before use

Report format:

```
SECURITY: [PASS | WARN | FAIL]
- {issue}: {file}:{line}, {recommendation}
```

## Step 3: TypeScript audit

```bash
npx tsc --noEmit 2>&1 | head -40
```

Also check manually:

- No `as any` casts (search: `grep -n "as any" {file}`)
- No `!` non-null assertions on values that could genuinely be null
- Props interfaces defined for every component
- Return types explicit on all async functions

Report:

```
TYPESCRIPT: [PASS | WARN | FAIL]
- {issue}: {file}:{line}
```

## Step 4: Performance review

- `<img>` tags instead of `next/image` → flag
- Missing `sizes` prop on responsive images → flag
- `useEffect` fetching data that should be a Server Component → flag
- Missing `staleTime` on React Query queries → flag
- Any route imports that could be `dynamic(() => import(...))` → flag
- `select("*")` in database queries → flag

Report:

```
PERFORMANCE: [PASS | WARN | FAIL]
- {issue}: {file}:{line}
```

## Step 5: Accessibility audit

- Every `<button>` with only an icon has `aria-label`
- Every form `<input>` has an associated `<label htmlFor=...>`
- No `onClick` on `<div>`, use `<button>` or add `role="button"` + `tabIndex={0}` + `onKeyDown`
- No focus styles removed without replacement
- Images have `alt` text (meaningful or empty string for decorative)

Report:

```
ACCESSIBILITY: [PASS | WARN | FAIL]
- {issue}: {file}:{line}
```

## Step 6: Error state audit

Every component that fetches async data needs all three:

- Loading state (skeleton, not spinner-only)
- Error state (friendly message + retry button)
- Empty state (illustrated message + CTA)

Search for components with `isLoading` or `useQuery` and verify all three are handled.

Report:

```
ERROR STATES: [PASS | WARN | FAIL]
- Missing {state} in {component}: {file}:{line}
```

## Step 7: Mobile / responsive audit

- Any fixed pixel widths in layout? (`width: 400px` instead of `max-w-md`)
- Grid that doesn't collapse on mobile? (missing `grid-cols-1 md:grid-cols-...`)
- Text that overflows on small screens? (long strings without `truncate` or `break-words`)

Report:

```
RESPONSIVE: [PASS | WARN | FAIL]
```

## Step 8: Final verdict

```
━━━━━━━━━━━━━━━━━━━━━━━━━━
REVIEW VERDICT
━━━━━━━━━━━━━━━━━━━━━━━━━━
SECURITY:      PASS / WARN / FAIL
TYPESCRIPT:    PASS / WARN / FAIL
PERFORMANCE:   PASS / WARN / FAIL
ACCESSIBILITY: PASS / WARN / FAIL
ERROR STATES:  PASS / WARN / FAIL
RESPONSIVE:    PASS / WARN / FAIL

SHIP: YES / NO (fix required items first)

Critical issues ({count}):
  1. {most important fix}
  2. ...

Nice-to-have ({count}):
  1. ...
━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Any FAIL = do not ship. Fix the fails, then re-run.
