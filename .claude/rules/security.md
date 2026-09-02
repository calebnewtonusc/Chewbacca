---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.py"
---

# Security Rules

## SQL / database

- **Never interpolate user input into SQL**: always use parameterized queries (Supabase `.eq()` / `.filter()`, pg `$1` params, never string interpolation in raw queries).
- Multi-step DB operations (insert+insert, update+delete, read-modify-write) must use transactions.

## Secrets and credentials

- **Never log secrets, tokens, passwords, or PII**: not even at `debug` level.
- Secrets live in env vars only. Never commit `.env` files. Document all required vars in `.env.example`.
- Redact sensitive fields before logging or broadcasting to SSE/WebSocket.

## Authentication and authorization

- **Never trust user-supplied IDs without ownership verification**: always join on the authenticated user's ID.
- Validate all user-supplied IDs server-side before acting on them.
- Destructive operations require explicit confirmation or re-auth.

## Input handling

- Type external data as `unknown` and narrow before use, never `as any` on untrusted input.
- `dangerouslySetInnerHTML` only with a sanitizer (DOMPurify), never with raw user content.
- No `eval()` or `new Function()` with user-supplied strings.

## Network / SSRF prevention

- Validate URLs from user input: resolve DNS first, then check the resolved IP is not loopback/private (`127.x`, `10.x`, `192.168.x`, `169.254.x`).
- HTTP allowlists for outbound requests in agent/automation code.

## Pre-merge security checklist

Before merging any PR that touches auth, payments, data access, or external calls:

- [ ] No secrets in source or logs
- [ ] User-supplied IDs verified against authenticated session
- [ ] SQL uses parameterized queries
- [ ] `dangerouslySetInnerHTML` absent or sanitized
- [ ] Outbound HTTP validates destination
- [ ] Error messages don't leak stack traces or internal paths to the client
