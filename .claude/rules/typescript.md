---
paths:
  - "**/*.ts"
  - "**/*.tsx"
---

# TypeScript Rules

**Run `tsc --noEmit` before declaring anything done.** Zero errors is the bar — not "it mostly works".

**Strict mode is assumed.** `strict: true` is set in all tsconfigs. Honor it.

**No implicit `any`.** If a value is coming from an external source (API response, JSON parse, `req.body`), type it as `unknown` and narrow with a type guard or Zod schema.

---

## Supabase Patterns

**Typed client — always use generated types:**

```typescript
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@/types/supabase";

const supabase = createClient<Database>(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);
```

**Server-side (App Router) — use `createServerClient`:**

```typescript
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

export function createSupabaseServer() {
  const cookieStore = cookies();
  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { get: (name) => cookieStore.get(name)?.value } },
  );
}
```

**Type-safe queries — destructure the data, narrow the error:**

```typescript
const { data, error } = await supabase
  .from("projects")
  .select("*")
  .eq("id", id)
  .single();
if (error) throw new Error(error.message);
// data is typed from Database
```

**Generate types after schema changes:**

```bash
npx supabase gen types typescript --project-id <id> > src/types/supabase.ts
```

---

## Zod Patterns

**Every API route body must be Zod-validated:**

```typescript
import { z } from "zod";

const schema = z.object({
  name: z.string().min(1).max(100),
  email: z.string().email(),
  role: z.enum(["admin", "user"]),
});

const parsed = schema.safeParse(req.body);
if (!parsed.success) {
  return Response.json({ error: parsed.error.flatten() }, { status: 400 });
}
```

**Infer types from schemas — don't duplicate:**

```typescript
type CreateProjectInput = z.infer<typeof createProjectSchema>;
```

---

## App Router Patterns

**Server Components are default**: only opt into `"use client"` when you need:

- `useState`, `useEffect`, event handlers
- browser APIs
- Framer Motion animations

**Typed page params:**

```typescript
interface PageProps {
  params: { id: string };
  searchParams: { [key: string]: string | string[] | undefined };
}

export default function Page({ params }: PageProps) {
  // ...
}
```

**Metadata export (every page):**

```typescript
export const metadata: Metadata = {
  title: "Page Title",
  description: "Page description",
};
```

---

## Utility Types: Use These

```typescript
// Pick specific fields
type ProjectPreview = Pick<Project, "id" | "name" | "created_at">;

// Make nullable fields required
type RequiredProject = Required<Project>;

// Partial for update payloads
type UpdatePayload = Partial<Pick<Project, "name" | "description">>;

// Non-nullable
type NonNullId = NonNullable<Project["id"]>;
```

---

## Import Order

1. Node built-ins
2. External packages (react, next, etc.)
3. Internal absolute (`@/components/...`)
4. Internal relative (`../`, `./`)

**Never use `require()` in TypeScript files**: use ESM `import`.

---

## What NOT to Do

- `as any`: use `unknown` + type guard instead
- `!` non-null assertion on values that could genuinely be null — check first
- Separate interface and type when one will do — pick one style and stick to it
- `Object.keys(x).forEach` when you want `Object.entries(x)` — be explicit
- Casting `req.params as any` — type the route generics properly
