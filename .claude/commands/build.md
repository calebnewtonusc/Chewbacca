---
description: Plan, build, type, smoke-test, and push a feature, end to end
allowed-tools: Bash(npm:*), Bash(npx:*), Bash(git:*), Bash(gh:*), Bash(ls:*), Bash(cat:*), Read, Write, Edit, Glob, TodoWrite
argument-hint: "<feature description>"
---

# Build

Build `$ARGUMENTS`, plan it, write it, type it, test it, push it.

## Step 0: Parse the feature

Extract from `$ARGUMENTS`:

- What does this feature **do**? (user-facing behavior)
- What files will it **touch**? (infer from codebase structure)
- What **data** does it need? (props, API, DB)

## Step 1: Plan in 3 steps

Before writing a single line of code, output exactly:

```
PLAN
1. [First thing to build, most foundational]
2. [Second thing, depends on step 1]
3. [Third thing, integration + wiring]
```

Keep it tight. No step should take more than ~100 lines of code. If it would, split the feature.

## Step 2: Check what exists

```bash
# Find related files
ls src/components/ src/app/ src/lib/ 2>/dev/null | head -30

# Check if there are similar features to model after
grep -r "similar_keyword" src/ --include="*.tsx" --include="*.ts" -l 2>/dev/null | head -5
```

Don't rebuild what already exists. Extend it.

## Step 3: Build it

Follow the plan. For each step:

- Write TypeScript, no implicit `any`, strict types throughout
- Use shadcn/ui components, never build raw primitives
- Use Tailwind, no inline styles, no raw CSS classes
- Add Lucide React icons, never emoji as icons
- Handle all three states: loading (skeleton), error (ErrorMessage), empty (EmptyState)

If the feature touches the database:

```typescript
// Always use typed Supabase client
import type { Database } from "@/types/supabase";
// Always select specific columns, never select("*")
// Always check .error before accessing .data
```

If the feature hits an API:

```typescript
// Always Zod-validate the response
// Always handle network errors
// Always show loading + error states
```

## Step 4: Add TypeScript types

After writing the code, audit every `any`:

```bash
grep -n "any" src/**/*.ts src/**/*.tsx 2>/dev/null | grep -v "// ok:" | head -20
```

Fix each one. Infer types from Supabase schema and Zod schemas, never manually duplicate type shapes.

## Step 5: Write a smoke test

Create `{filename}.test.ts` or `{filename}.test.tsx`:

```typescript
import { describe, it, expect, vi } from "vitest";

describe("{Feature name}", () => {
  it("renders without crashing", () => {
    // render the component with minimal required props
    // assert it doesn't throw
  });

  it("shows loading state", () => {
    // render with isLoading=true
    // assert skeleton is present
  });

  it("shows error state", () => {
    // render with error prop
    // assert error message is present
  });

  it("happy path, {main behavior}", () => {
    // mock the data
    // assert the expected output renders
  });
});
```

Run it:

```bash
npm test -- --run {filename} 2>/dev/null || echo "No test runner configured yet"
```

## Step 6: Push to GitHub

```bash
git add {list all created/modified files by name, never git add .}
git commit -m "feat: {what was built, one line}"
git push
```

Report the commit hash and GitHub URL.

## Quality Gate Before Marking Done

- [ ] No implicit `any` in new code
- [ ] All three states handled (loading, error, empty) on any async component
- [ ] Mobile layout doesn't break (check at 375px conceptually)
- [ ] Smoke test exists and passes
- [ ] Committed and pushed
