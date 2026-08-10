---
description: Analyze an error, find root cause, propose 3 fixes ranked by likelihood, implement the top one
allowed-tools: Bash(npm:*), Bash(npx:*), Bash(grep:*), Bash(git:*), Read, Glob, Edit
argument-hint: "<error message or description>"
---

# Debug

Debug `$ARGUMENTS`. Find the root cause. Fix it.

## Step 1: Parse the error

From `$ARGUMENTS`, identify:

- **Error type**: TypeError / SyntaxError / ReferenceError / HTTP 500 / Build error / Runtime crash / etc.
- **Error message**: the exact string
- **Stack trace**: if provided, read every frame

If no stack trace was provided, ask for it before proceeding. The stack trace is the map.

## Step 2: Locate the source

```bash
# Find the file referenced in the error
grep -rn "{key phrase from error}" src/ --include="*.ts" --include="*.tsx" | head -10

# If it's a build error, check recent changes
git diff HEAD~3 --name-only
git log --oneline -5
```

Read the exact file and line number. Do not guess — go there first.

## Step 3: Check your assumptions

Before proposing fixes, verify:

1. What is the actual value at the crash point? (add a `console.log` mentally or via edit)
2. Is the type what you expected? (TypeScript might show the truth)
3. Is this a null/undefined access? Check the call chain upstream.
4. Is this an async issue? (accessing data before it's loaded?)
5. Is this a version mismatch? (check `package.json` for the relevant package)

## Step 4: Propose 3 fixes: ranked by likelihood

Output exactly this format:

```
ROOT CAUSE
{1-2 sentence explanation of why this is happening}

FIX 1 (most likely — {confidence}%)
{what to change and why}

FIX 2 (if Fix 1 is wrong — {confidence}%)
{alternative cause + what to change}

FIX 3 (edge case — {confidence}%)
{the weird case that sometimes causes this}
```

## Step 5: Implement Fix 1

Apply the most likely fix. Make the minimum change needed — don't refactor surrounding code.

After the fix:

```bash
# Verify it compiles
npx tsc --noEmit 2>&1 | head -20

# If it was a runtime error, check the relevant test
npm test -- --run {relevant test file} 2>/dev/null || echo "No test"
```

## Step 6: If Fix 1 doesn't work

Say so explicitly. Don't pretend it's fixed. Then:

1. Implement Fix 2
2. If Fix 2 also fails, implement Fix 3
3. If all three fail, escalate: provide a minimal reproduction and suggest where to look next

## Common patterns by error type

**"Cannot read properties of undefined (reading 'X')"**
→ Null check missing. The object upstream is undefined. Check the API response shape and add optional chaining or a guard.

**"X is not a function"**
→ The thing you're calling isn't what you think. `console.log(typeof X)`. Often: destructuring wrong field, import path wrong, wrong export type.

**Next.js build error: "useX is not a function" / hydration mismatch**
→ Client-only code in a Server Component. Add `"use client"` to the component.

**"NEXT_PUBLIC_X is undefined"**
→ Missing env var. Check Vercel dashboard. Check `.env.local`. Restart dev server after adding.

**Supabase "row-level security policy" error**
→ RLS is blocking the query. The user doesn't have permission. Check `auth.uid()` in the policy matches the row's `user_id`.

**"Module not found" at build**
→ Path alias wrong, file doesn't exist at that path, case sensitivity (Mac vs Linux). Check `tsconfig.json` paths.

**React "Too many re-renders"**
→ State update inside render (no dependency array on useEffect, or setState called unconditionally). Read the component, find the cycle.

**Stripe "No such customer"**
→ Customer ID mismatch between test and production mode. Check `STRIPE_SECRET_KEY` is consistent with the customer data.
