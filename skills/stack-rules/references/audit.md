---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.py"
---

# Audit Standards

When performing a `/audit` on any codebase, evaluate across all six lenses below. Report with grades (A/B/C/D/F) and specific line-level findings.

---

## Lens 1: Security

- **Secrets exposure**: No API keys, tokens, or passwords in source files. `.env` never committed. `process.env.*` used correctly.
- **SQL injection**: All DB queries use parameterized queries or ORM methods — no string interpolation into SQL.
- **Auth gaps**: Every route that touches user data has auth checks. RLS enabled on all Supabase tables.
- **SSRF**: No user-controlled URLs passed directly to `fetch()` without validation.
- **XSS**: No `dangerouslySetInnerHTML` without sanitization. No raw user content rendered unescaped.
- **CORS**: API routes have explicit CORS headers — not wildcard `*` in production.
- **Rate limiting**: Any public-facing endpoint has rate limiting or is behind auth.

## Lens 2: Type Safety

- No `any` casts in TypeScript — flag every one.
- All external data (API responses, query params) narrowed through Zod or type guards.
- Supabase queries typed via generated `Database` types.
- No missing null checks on optional fields.

## Lens 3: Error Handling

- Every `async/await` block has try/catch or `.catch()`.
- API routes return typed error responses with correct HTTP status codes.
- User-facing errors show friendly messages — not raw stack traces.
- Database errors logged server-side, never exposed to client.

## Lens 4: Performance

- No N+1 queries — batch DB calls where possible.
- Images use `next/image` — no raw `<img>` tags.
- No blocking operations in React render — data fetching in server components or React Query.
- Bundle size: no route over 250KB first load JS (flag anything over 150KB).
- No unnecessary `useEffect` for data that could be server-fetched.

## Lens 5: Code Quality

- Dead code: unused imports, variables, functions, components.
- Console.logs left in — all must be removed before production.
- Duplicated logic that should be extracted to a shared util.
- Components over 200 lines — should be split.
- Any TODO or FIXME comments that are load-bearing (blocking correctness, not just aspirational).

## Lens 6: Design Quality

- Every UI component has hover states.
- No raw `<button>` without styling.
- No system fonts — Inter or Geist only.
- Mobile responsive — check at 375px and 768px breakpoints.
- Loading states present on all async data.
- Empty states present on all list/table views.
- Error states present and user-friendly.

---

## Audit Report Format

```
## Audit: {project name}
**Date:** {date}

### Security : Grade: {A-F}
- [CRITICAL] {finding} — {file:line}
- [HIGH] {finding}
- [MEDIUM] {finding}

### Type Safety: Grade: {A-F}
...

### Error Handling: Grade: {A-F}
...

### Performance: Grade: {A-F}
...

### Code Quality: Grade: {A-F}
...

### Design Quality: Grade: {A-F}
...

### Overall Grade: {A-F}
**Top 3 must-fix before shipping:**
1. ...
2. ...
3. ...
```

---

## Triage Priority

- **CRITICAL**: Ship blocker. Do not proceed until fixed.
- **HIGH**: Fix this sprint.
- **MEDIUM**: Fix next sprint or in the same PR if quick.
- **LOW**: Backlog — document it, move on.
