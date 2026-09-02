---
description: Refactor a file for readability and performance, add types, split if over 200 lines, clean up
allowed-tools: Bash(npm:*), Bash(npx:*), Bash(grep:*), Bash(wc:*), Read, Write, Edit, Glob
argument-hint: "<file path>"
---

# Refactor

Refactor `$ARGUMENTS`. Improve readability and performance. Add missing types. Split if needed.

## Step 1: Read the file

Read the full file. Understand what it does before changing anything.

Measure:

```bash
wc -l "$ARGUMENTS"
```

If over 200 lines, it needs to be split (see Step 5).

## Step 2: TypeScript audit

Find all type debt:

```bash
grep -n ": any\|as any\|// @ts-ignore\|// @ts-expect-error" "$ARGUMENTS"
```

For each `any`:

1. Infer the actual type from usage
2. Check if a Supabase-generated type or Zod-inferred type exists
3. Replace with the specific type

For every function that lacks a return type:

```typescript
// Before
async function getUser(id) {
  // ...
}

// After
async function getUser(id: string): Promise<User | null> {
  // ...
}
```

## Step 3: Readability improvements

Apply these in order:

**Extract magic values**

```typescript
// Before
if (retries > 3) { ... }
// After
const MAX_RETRIES = 3;
if (retries > MAX_RETRIES) { ... }
```

**Name boolean flags meaningfully**

```typescript
// Before
const x = data && data.length > 0 && !loading;
// After
const hasResults = data && data.length > 0 && !loading;
```

**Extract complex conditions**

```typescript
// Before
if (user.role === 'admin' && user.verified && !user.suspended) { ... }
// After
const canAccessDashboard = user.role === 'admin' && user.verified && !user.suspended;
if (canAccessDashboard) { ... }
```

**Extract repeated JSX into sub-components**
If the same structure appears 3+ times in JSX, extract to a named component.

**Flatten nested callbacks**
Replace `.then().then().catch()` chains with `async/await`.

## Step 4: Performance improvements

Check for:

- `useEffect` dependencies that could cause infinite loops
- Missing `useMemo` on expensive computed values (arrays `.filter().map()` inside render)
- Missing `useCallback` on functions passed as props to memoized children
- `console.log` statements left in (remove them)
- Unused imports (remove them)

```bash
# Find unused imports with ESLint
npx eslint "$ARGUMENTS" --rule '{"no-unused-vars": "error"}' 2>/dev/null | head -20
```

## Step 5: Split if over 200 lines

If the file is over 200 lines:

1. Identify the distinct concerns:
   - Data fetching logic → `use{Feature}Query.ts` hook
   - Business logic → `{feature}.utils.ts`
   - Type definitions → add to `types.ts` or top of file
   - Sub-components → separate `{SubComponent}.tsx` files

2. Extract each concern into its own file
3. Update imports in the original file
4. Verify nothing breaks: `npx tsc --noEmit`

Target: the refactored main file should be under 150 lines.

## Step 6: Verify nothing broke

```bash
npx tsc --noEmit 2>&1 | head -20
npx eslint "$ARGUMENTS" 2>&1 | head -20
npm test -- --run 2>/dev/null | tail -10
```

Zero new errors after refactor. If a test breaks, fix it, don't revert the refactor.

## What NOT to do

- Don't change behavior, only change structure
- Don't rename public APIs or exported function names
- Don't add new features while refactoring
- Don't change test files to make tests pass, fix the source
- Don't add comments explaining obvious code, rename the variable instead
