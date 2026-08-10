---
name: stack-rules
description: Enforces this kit's standards for Next.js, React, Supabase, and Vercel work. Use when writing or reviewing UI components, API routes, database schemas or queries, deployment config, styling and design, scroll animations, accessibility, performance, state management, tests, or when running a pre-ship audit. Covers shadcn/ui component patterns, Zod-validated App Router routes, RLS policies, Core Web Vitals budgets, WCAG contrast, and the UX laws checklist.
---

# Stack rules

Twelve standards files for the stack this kit assumes. They load only when the
work actually touches the relevant area, which is the point: importing all of
them on every session costs roughly 12,500 tokens, and a Python service that
will never render a button should not pay for the Tailwind rules.

The six genuinely universal standards (git, security, writing, naming,
typescript, review-discipline) are not here. Those are `@`-imported by
`CLAUDE.md` and always in context, at about 3,700 tokens.

## Which file to read

Read the specific file before writing code in its area. Do not read all twelve.

| Working on                                       | Read                           |
| ------------------------------------------------ | ------------------------------ |
| React components, shadcn/ui, loading/empty states | `references/components.md`     |
| API routes, Zod validation, error shapes          | `references/api.md`            |
| Supabase schema, RLS, migrations, queries         | `references/database.md`       |
| Vercel deploys, env vars, pre-deploy checks       | `references/deployment.md`     |
| Color, typography, spacing, the visual system     | `references/design.md`         |
| Images, fonts, bundle size, Core Web Vitals       | `references/performance.md`    |
| React Query, URL state, Zustand, form state       | `references/state.md`          |
| Semantic HTML, focus, ARIA, WCAG contrast         | `references/accessibility.md`  |
| Scroll animations, parallax, reveal effects       | `references/scroll-effects.md` |
| Unit, integration, and E2E tests                  | `references/testing.md`        |
| Hick's, Fitts's, Miller's, layout decisions       | `references/ux-laws.md`        |
| Pre-ship audit across all six lenses              | `references/audit.md`          |

## How to apply them

These are standards, not suggestions. When a file says "never build a custom
button, use shadcn/ui," that is the expected output, not one option among
several. If a rule genuinely does not fit the project, say so and explain why
rather than quietly ignoring it.

When a task spans areas, read each relevant file. Building a settings page that
saves to Supabase means `components.md`, `state.md`, and `database.md`, plus
`accessibility.md` before it ships.
