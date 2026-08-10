---
paths:
  - "**/*.test.ts"
  - "**/*.test.tsx"
  - "**/*.spec.ts"
  - "**/*.spec.tsx"
  - "**/*.test.js"
  - "**/*.test.py"
  - "**/tests/**"
  - "**/__tests__/**"
---

# Testing Rules

## Test tiers

| Tier        | Command                                | When                      |
| ----------- | -------------------------------------- | ------------------------- |
| Unit        | `npm test` / `pytest`                  | Always — no external deps |
| Integration | `npm run test:integration`             | When DB/API available     |
| E2E         | `npm run test:e2e` / `playwright test` | Before release            |

## Patterns

- Every bug fix requires a regression test that would have caught the bug.
- Don't only test the happy path — test the exact error case that was broken.
- Use `tempfile` / `tmp` dirs for test artifacts — never hardcode `/tmp/specific-path`.
- Tests must not make real network requests. Use mocks, stubs, or `msw` interceptors.
- Tests must not mutate shared global state without cleanup (`afterEach`/`afterAll`).
- Async tests: always `await` or `return` the Promise — a test that passes silently is worse than one that fails loudly.

## TypeScript

- Prefer `vi.fn()` / `jest.fn()` over manual mock classes.
- Mock at the boundary (HTTP, DB, filesystem) — don't mock your own internal modules.
- Use `expect.objectContaining()` for partial matches rather than full snapshot equality when the shape matters more than exact values.

## Python

- Use `pytest` fixtures, not `setUp`/`tearDown`.
- `monkeypatch` over module-level patches — keeps tests isolated.
- Mark slow tests with `@pytest.mark.slow` so CI can skip them.

## What NOT to do

- `catch (e) {}` in tests — always assert or rethrow.
- Testing implementation details (private function internals) instead of behavior.
- Hardcoding dates/times — use `vi.useFakeTimers()` or `freezegun`.
- `console.log` left in tests — use assertions instead.
