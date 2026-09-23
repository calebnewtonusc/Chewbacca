---
name: reviewing-changes
description: "Review code for real problems before it goes anywhere. Use when the user asks to review this, look over my code, check this for bugs, tell me if this is any good, find what is wrong with this, review my PR, or asks whether a change is safe to merge or ready for someone else to read. Also use before opening a pull request, after finishing a feature, or when a reviewer has called something sloppy."
requires: [git]
---

# Reviewing changes

Find real problems. Style opinions waste the one pass someone will actually read,
and a review that opens on naming teaches the author that reviews are noise.

The agent owns routine review and repair. Do not hand the diff to the user as a
required code-review step. Use a separate reviewer context, fix substantiated
findings within scope, rerun affected checks, and review the changed result.
Ask the user only for a genuine unresolved product decision or required authority.
Independent automated review reduces risk; it does not guarantee bug-free code.

For a local Git checkout, `review-gate run --repo PATH` starts a separate read-only
Codex reviewer. `review-gate check --repo PATH` checks whether its receipt still
matches the current files. A changed file invalidates the receipt. Review errors,
incomplete coverage and findings are not clean reviews. Read the report, resolve
concrete findings, then run again. After three unsuccessful repair cycles, diagnose
the unresolved cause and report it plainly instead of claiming completion or
asking the user to perform the review. Preserve unrelated edits.

If a native Codex Stop cannot finish because review remains unresolved, use
`review-gate report-incomplete --session-id ID --turn-id ID` after a recorded
failed review attempt. Return the exact generated report. This permits truthful
status reporting only: it never creates a clean receipt or clears review duties.
Changed files, a different turn, or missing failure evidence invalidate it.

Native tool observation freezes the repository revision before changes so a
commit cannot remove work from the review scope. For a standalone review of
already committed work without native observation, supply `--base COMMIT` to
`review-gate run`. Without an existing scope or explicit base, the initial
standalone review covers uncommitted changes from the current HEAD. An
existing frozen base cannot silently be narrowed by a later invocation.

## Get the code first

Never review from memory of what was written. Read the actual diff.

```sh
git diff HEAD                 # uncommitted
git diff main...HEAD          # the whole branch, against its merge base
git diff --stat               # what moved, before reading any of it
```

For a GitHub PR: `gh pr diff <n>` and `gh pr view <n> --json title,body`.

If the diff is large, read the stat first and review in dependency order: schema,
then the code that reads it, then the callers. Reviewing a caller before the
thing it calls produces confident wrong comments.

## What actually matters, in order

**1. Does it do what it claims.** Read the description, then check the code does
that and only that. An unrelated change smuggled into a diff is the single most
common source of a surprise regression, and it is invisible unless someone asks.

**2. Correctness at the boundaries.** Empty list, one element, null, the value
arriving as a string when a number was assumed, the second call after the first
already wrote. Walk one concrete failing input end to end rather than reasoning
about the code in the abstract. If you cannot construct one, say so instead of
implying you found nothing.

**3. Security, on every diff, no exceptions:**
- User input reaching a query as string interpolation rather than a parameter
- A secret in the source: hardcoded key, token, password, a `.env` value inlined
- A protected route that never checks the caller, or trusts an id from a request
  body without verifying ownership
- A query returning rows that could belong to someone else
- Logging that prints a token, a password, or personal data

**4. Error paths.** A swallowed exception is a bug, not a style choice. Expected
failures (validation, a 404) and unexpected ones (the database is down) need
different handling, and code that treats them the same will hide a real outage.

**5. What the change breaks elsewhere.** When a column, an enum value, or a
function signature changes, grep for every other caller. Fixing one call site and
declaring victory is how a schema change ships half-applied.

**6. Tests that pin the bug, not the behavior.** If an assertion encodes a wrong
value because that is what the code currently returns, both are wrong.

## Reporting

Lead with the most severe thing. For each finding: the file and line, one
sentence on what breaks, and a concrete input or sequence that triggers it. A
finding without a failure scenario is a guess wearing a suit.

Separate what must change from what would be nice. Say plainly when the diff is
clean: a review that manufactures findings to look thorough costs more trust than
it buys, and the next one gets skimmed.

If the author is the user, do not soften it. If a reviewer has already called the
code sloppy, concede the pattern before defending any instance, and fix the whole
category rather than only the lines they flagged.
