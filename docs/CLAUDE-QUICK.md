# Claude Quick Start

Drop this into any project as `CLAUDE.md` for instant quality improvement. For the full 700-line version, see [CLAUDE.md](../CLAUDE.md).

## Stack

- Next.js 14+ (App Router), Tailwind CSS, shadcn/ui, Lucide React icons
- TypeScript strict mode, Zod for validation
- Supabase for auth + database, Vercel for deployment

## Design

- Background: `#0a0a0a` or `zinc-950`. Never pure black or white.
- Text: `white` / `zinc-50` primary, `zinc-400` muted. Accent: `indigo-500`.
- Font: Inter or Geist via `next/font`. Never system fonts.
- Cards: `bg-zinc-900 border border-zinc-800 rounded-2xl p-6 hover:border-zinc-700 transition-all`
- Buttons: `bg-indigo-600 hover:bg-indigo-500 text-white font-semibold px-6 py-2.5 rounded-xl cursor-pointer`
- Every button needs hover + active + `cursor-pointer` + `transition-all duration-200`
- Every data component needs loading (skeleton), empty, and error states

## Components

Always use shadcn/ui. Never build raw buttons, inputs, dialogs, or selects from scratch.

```bash
npx shadcn@latest add button card input badge dialog skeleton toast
```

## API Routes

- Validate all input with Zod
- Return `{ data }` on success, `{ error }` on failure
- Use proper HTTP status codes (200, 201, 400, 401, 404, 500)

## Database

- Always enable RLS on every Supabase table
- Use prepared statements (never string interpolation for queries)
- Soft delete with `deleted_at` column, never hard delete user data

## Performance

- Use `next/image` for all images, `next/font` for fonts
- Default to Server Components. Add `"use client"` only when needed.
- Keep it as deep in the tree as possible

## Git

- Stage by filename, never `git add -A` or `git add .`
- Commit format: `feat:`, `fix:`, `chore:`, `docs:`
- Push to GitHub when done. Never wait to be asked.

## Prohibitions

- No Times New Roman or system serif fonts
- No flat white/gray backgrounds
- No `<button>` without styling, no `<a>` with default blue
- No layout that breaks on mobile
- No missing loading/empty/error states
- No `any` types in TypeScript
- No `console.log` in production code
