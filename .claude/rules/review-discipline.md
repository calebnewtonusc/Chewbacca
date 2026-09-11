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

---

## Where a lesson goes

Review feedback is worth more than the one line it flagged, and it gets thrown
away when nobody decides where it lives. Route every correction, once:

- **A reusable judgment** (how to name this class of thing, when this pattern is
  the wrong shape, what a good version looks like) goes in the standing doc that
  owns that judgment: a rule in `.claude/rules/`, a skill, `design.md` in a UI
  repo. Prose, where the next person reads it before writing.
- **A repeatable mechanical failure** (this exact ordering breaks, this value
  silently drifts, this path is wrong on a fresh machine) becomes a **test next
  to the implementation**. Not a paragraph. A paragraph does not fail CI.

If a correction produces neither, it was not a lesson, it was a typo. Fix it and
move on. If it produces both, write both.

The failure this prevents: the same class of bug caught three times in review,
explained well each time, never written down anywhere, because "I'll remember"
is not a storage medium.

## Anchor a constant to the evidence that set it

Any number, bound, threshold, timeout, or limit that could plausibly be a
different number needs a comment saying **what happened** that made it this one.
Not the reasoning. The observation.

```js
// Bad: reasoning only. Unfalsifiable, so nobody can ever safely change it.
const MAX_HOPS = 1;  // walking too far up captures unrelated directories

// Good: the evidence. Now a reader knows what breaks if they raise it, and
// can go re-measure.
// Unbounded, one `~/Desktop/Home` registration was an ancestor of 255 of 290
// candidates and captured all of them: a year of unrelated work filed under
// one project because of a registration nobody remembers making.
const MAX_HOPS = 1;
```

A constant with only a rationale gets raised by the next person who finds the
rationale unconvincing. A constant carrying its incident report does not.

This applies hardest to matcher thresholds, retry counts, cache TTLs, and any
bound protecting against a blow-up you have actually seen. If you cannot state
the evidence, say so in the comment (`// guessed, never measured`), which is
honest and tells the next reader exactly how much the number is worth.

## Scanning must not write

Any operation that imports, syncs, matches, or reconciles splits in two:

- **scan** opens files, matches, and answers. It creates nothing, moves nothing,
  and deletes nothing. Running it twice changes nothing.
- **apply** writes, and writes **only the keys it was handed** by a scan the
  user actually looked at.

The preview the user approved is then exactly the work that happens, which is
the only thing that makes a preview worth reading. An importer that creates a
row "just to check" has already made the decision it was asking about.

Ship the reverse too. Anything that writes in bulk gets an undo that touches
only rows its own apply created, identified by an origin field written at
insert time, never inferred afterward by shape.
