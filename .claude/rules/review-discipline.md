---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "services/**/*.ts"
---

# Review & Fix Discipline

**Fix the pattern, not just the instance.** When a reviewer flags a bug, search the entire codebase for all instances of that same pattern before marking it fixed.

**Read before judging.** Never comment on code you haven't actually read. Verify line numbers against the actual file content, not just the diff.

**TypeScript safety rules:**

- No `as any` casts without a comment explaining why it's safe
- No non-null assertions (`!`) on values that could legitimately be null/undefined
- No `@ts-ignore` without explaining the underlying issue
- Use `unknown` instead of `any` for external data; narrow with type guards

**Async correctness:**

- Never `await` inside a loop when calls are independent, use `Promise.all`
- Never fire-and-forget Promises without error handling
- Don't mix `async/await` and `.then()/.catch()` chains in the same function

**Error handling:**

- Don't swallow errors silently (`catch (e) {}` with no logging is a bug)
- Distinguish expected errors (validation, 404) from unexpected ones (DB down, bug)
- Return early on errors rather than nesting success in `if` blocks

**Schema consistency:**

- Enum values must match exactly across DB schema, TypeScript types, and runtime code
- When adding a column to a schema, check ALL routes that query that table
- Foreign keys that are NOT NULL in schema must be provided in every insert

**Security:**

- Never interpolate user input into SQL, always use parameterized queries
- Never log secrets, tokens, passwords, or PII (even at debug level)
- Validate all user-supplied IDs, never trust a userId from a request body without verifying ownership

**Regression tests:**

- Every bug fix must include a test that would have caught the bug
- Don't only test the happy path, test the error case that was actually broken
