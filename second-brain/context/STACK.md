# Stack: Preferred Technologies and Standards

**Updated:** When stack preferences change.

---

## Frontend

- **Framework:** Next.js (App Router)
- **Styling:** Tailwind CSS
- **Components:** shadcn/ui (never build primitives from scratch)
- **Icons:** Lucide React
- **Fonts:** Geist or Inter via `next/font`
- **Animation:** Framer Motion
- **State (server):** React Query
- **State (client):** Zustand for shared UI, useState for local
- **Forms:** React Hook Form + Zod

## Backend

- **API routes:** Next.js App Router (`app/api/resource/route.ts`)
- **Validation:** Zod (always, never trust raw input)
- **Auth:** Supabase Auth
- **Database:** Supabase (PostgreSQL + pgvector)
- **ORM:** Drizzle or Supabase client with generated types

## AI

- **SDK:** Vercel AI SDK (`ai` package) for streaming
- **Model:** `claude-opus-5` default, `claude-sonnet-5` for cheaper high volume, `claude-haiku-4-5` for speed
- **Streaming:** Always stream, never buffer

## Deploy

- **Frontend:** Vercel
- **Backend/workers:** Railway
- **Database:** Supabase

## Design System

See `CLAUDE.md` for the full design system. Summary:

- Background: `zinc-950` or `#0a0a0a`
- Accent: `indigo-500/600`
- Cards: `bg-zinc-900 border border-zinc-800 rounded-2xl`
- Scroll-aware navbar: mandatory on every project

## Code Standards

- TypeScript strict mode — no `any`
- No `console.log` in production code
- No commented-out code
- No em dashes, no emojis in code or copy
- Imports: named exports preferred, barrel files only when justified
