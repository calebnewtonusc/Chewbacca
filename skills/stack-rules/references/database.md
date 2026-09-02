# Database Rules

## Default: Supabase + PostgreSQL

All projects use Supabase unless explicitly stated otherwise.

```ts
// Client-side (browser)
import { createBrowserClient } from "@supabase/ssr";

const supabase = createBrowserClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

// Server-side (API routes, server components)
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

const supabase = createServerClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  {
    cookies: {
      getAll() {
        return cookies().getAll();
      },
      setAll() {},
    },
  },
);
```

## Row-Level Security (RLS): Always Enable

Every table must have RLS enabled and explicit policies. Never leave a table with RLS disabled in production.

```sql
-- Enable RLS
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;

-- Users can only read their own rows
CREATE POLICY "Users can read own posts"
  ON posts FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own rows
CREATE POLICY "Users can insert own posts"
  ON posts FOR INSERT
  WITH CHECK (auth.uid() = user_id);
```

## Schema Conventions

- Table names: `snake_case`, plural (`users`, `blog_posts`, `user_profiles`)
- Column names: `snake_case`
- Primary key: `id uuid DEFAULT gen_random_uuid() PRIMARY KEY`
- Timestamps: `created_at timestamptz DEFAULT now()`, `updated_at timestamptz DEFAULT now()`
- Foreign keys: `{table_singular}_id` (e.g., `user_id`, `post_id`)
- Soft delete: `deleted_at timestamptz` (nullable, null means not deleted)

## Type Safety

Always generate types from Supabase schema:

```bash
npx supabase gen types typescript --project-id $PROJECT_ID > src/types/supabase.ts
```

Use the generated types in all queries:

```ts
import type { Database } from "@/types/supabase";

type Post = Database["public"]["Tables"]["posts"]["Row"];
type PostInsert = Database["public"]["Tables"]["posts"]["Insert"];
```

## Query Patterns

Fetch with error handling:

```ts
const { data, error } = await supabase
  .from("posts")
  .select("id, title, created_at")
  .eq("user_id", user.id)
  .order("created_at", { ascending: false })
  .limit(20);

if (error) throw new Error(error.message);
```

Insert:

```ts
const { data, error } = await supabase
  .from("posts")
  .insert({ title, content, user_id: user.id })
  .select()
  .single();
```

## Real-Time Subscriptions

```ts
const channel = supabase
  .channel("posts-changes")
  .on(
    "postgres_changes",
    { event: "INSERT", schema: "public", table: "posts" },
    (payload) => {
      // handle new post
    },
  )
  .subscribe();

// Cleanup
return () => supabase.removeChannel(channel);
```

## Migrations

Use Supabase CLI for schema migrations:

```bash
supabase migration new add_posts_table
# edit the generated SQL file
supabase db push
```

Never write raw DDL directly in the Supabase dashboard for anything that needs to persist, always migrate.

## Indexes

Add indexes for columns used in `WHERE`, `JOIN`, or `ORDER BY`:

```sql
CREATE INDEX posts_user_id_idx ON posts(user_id);
CREATE INDEX posts_created_at_idx ON posts(created_at DESC);
```

## Never Do These

- Never disable RLS without an explicit policy plan
- Never store passwords in the database, use Supabase Auth
- Never expose the service role key to the client
- Never use `select("*")` in production, always specify columns
- Never delete rows that users care about, soft delete with `deleted_at`
