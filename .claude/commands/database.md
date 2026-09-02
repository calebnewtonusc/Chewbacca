---
description: Design Supabase schema, write Drizzle migration, add RLS policies, generate TypeScript types
allowed-tools: Bash(npm:*), Bash(npx:*), Bash(supabase:*), Read, Write, Glob
argument-hint: "<feature description, what data does this feature need?>"
---

# Database

Design the database schema for `$ARGUMENTS`. Supabase + Drizzle ORM. RLS on everything.

## Step 1: Model the data

From `$ARGUMENTS`, identify:

- **Entities**: what are the nouns? (user, post, project, subscription, etc.)
- **Relationships**: 1:1, 1:many, many:many?
- **Ownership**: which rows belong to which user?
- **Access patterns**: what queries will be run most often?

Output an entity relationship diagram in text:

```
users (1) ──── (many) posts
posts (1) ──── (many) comments
users (1) ──── (1) profiles
```

## Step 2: Write the Supabase SQL migration

Create `supabase/migrations/{timestamp}_{feature}.sql`:

```sql
-- ==========================================
-- {Feature name} Schema
-- ==========================================

-- Enable required extensions (if not already)
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- {Table 1}
CREATE TABLE IF NOT EXISTS {table_name} (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- domain fields
  name        text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 255),
  description text,
  status      text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived', 'deleted')),

  -- metadata
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz  -- soft delete
);

-- Updated-at trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER {table_name}_updated_at
  BEFORE UPDATE ON {table_name}
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Indexes (always add for FK columns and common query columns)
CREATE INDEX {table_name}_user_id_idx ON {table_name}(user_id);
CREATE INDEX {table_name}_created_at_idx ON {table_name}(created_at DESC);
CREATE INDEX {table_name}_status_idx ON {table_name}(status) WHERE deleted_at IS NULL;

-- ==========================================
-- Row Level Security
-- ==========================================

ALTER TABLE {table_name} ENABLE ROW LEVEL SECURITY;

-- Users can only see their own rows (and non-deleted)
CREATE POLICY "{table_name}_select"
  ON {table_name} FOR SELECT
  USING (auth.uid() = user_id AND deleted_at IS NULL);

-- Users can only insert rows they own
CREATE POLICY "{table_name}_insert"
  ON {table_name} FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can only update their own rows
CREATE POLICY "{table_name}_update"
  ON {table_name} FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Users can only delete their own rows (use soft delete in app)
CREATE POLICY "{table_name}_delete"
  ON {table_name} FOR DELETE
  USING (auth.uid() = user_id);
```

## Step 3: Write the Drizzle schema

Create or update `src/db/schema/{table_name}.ts`:

```typescript
import {
  pgTable,
  uuid,
  text,
  timestamp,
  pgEnum,
} from "drizzle-orm/pg-core";

export const statusEnum = pgEnum("status", ["active", "archived", "deleted"]);

export const {tableName} = pgTable("{table_name}", {
  id:          uuid("id").defaultRandom().primaryKey(),
  userId:      uuid("user_id").notNull(),
  name:        text("name").notNull(),
  description: text("description"),
  status:      statusEnum("status").notNull().default("active"),
  createdAt:   timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt:   timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  deletedAt:   timestamp("deleted_at", { withTimezone: true }),
});

// TypeScript types auto-generated
export type {TablePascalCase} = typeof {tableName}.$inferSelect;
export type New{TablePascalCase} = typeof {tableName}.$inferInsert;
export type Update{TablePascalCase} = Partial<Pick<{TablePascalCase}, "name" | "description" | "status">>;
```

Update `src/db/schema/index.ts` to re-export.

## Step 4: Generate Supabase TypeScript types

After pushing the migration:

```bash
npx supabase gen types typescript --project-id YOUR_PROJECT_ID > src/types/supabase.ts
```

Or if using local Supabase:

```bash
npx supabase gen types typescript --local > src/types/supabase.ts
```

## Step 5: Write CRUD helpers

Create `src/lib/{table_name}.ts`:

```typescript
import { createServerClient } from "@supabase/ssr";
import type { Database } from "@/types/supabase";

type Row = Database["public"]["Tables"]["{table_name}"]["Row"];
type Insert = Database["public"]["Tables"]["{table_name}"]["Insert"];

// Always specific columns, never select("*")
const COLUMNS = "id, user_id, name, description, status, created_at" as const;

export async function list{TablePascalCase}(supabase: ReturnType<typeof createServerClient<Database>>) {
  const { data, error } = await supabase
    .from("{table_name}")
    .select(COLUMNS)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) throw new Error(error.message);
  return data;
}

export async function get{TablePascalCase}(
  supabase: ReturnType<typeof createServerClient<Database>>,
  id: string
) {
  const { data, error } = await supabase
    .from("{table_name}")
    .select(COLUMNS)
    .eq("id", id)
    .is("deleted_at", null)
    .single();

  if (error) throw new Error(error.message);
  return data;
}

export async function create{TablePascalCase}(
  supabase: ReturnType<typeof createServerClient<Database>>,
  input: Pick<Insert, "name" | "description">
) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Unauthorized");

  const { data, error } = await supabase
    .from("{table_name}")
    .insert({ ...input, user_id: user.id })
    .select(COLUMNS)
    .single();

  if (error) throw new Error(error.message);
  return data;
}

export async function update{TablePascalCase}(
  supabase: ReturnType<typeof createServerClient<Database>>,
  id: string,
  updates: Pick<Row, "name" | "description" | "status">
) {
  const { data, error } = await supabase
    .from("{table_name}")
    .update(updates)
    .eq("id", id)
    .select(COLUMNS)
    .single();

  if (error) throw new Error(error.message);
  return data;
}

// Soft delete, never hard delete user data
export async function delete{TablePascalCase}(
  supabase: ReturnType<typeof createServerClient<Database>>,
  id: string
) {
  const { error } = await supabase
    .from("{table_name}")
    .update({ deleted_at: new Date().toISOString(), status: "deleted" })
    .eq("id", id);

  if (error) throw new Error(error.message);
}
```

## Step 6: Verify RLS

Test that RLS works:

```bash
# Using Supabase Studio or CLI
# 1. Create two test users
# 2. Insert a row as user A
# 3. Query as user B: should return 0 rows
# 4. Try to update as user B: should fail with RLS error
```

## RLS patterns by use case

**Public read / auth write** (blog posts, public profiles):

```sql
CREATE POLICY "public_select" ON posts FOR SELECT USING (true);
CREATE POLICY "owner_insert"  ON posts FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "owner_update"  ON posts FOR UPDATE USING (auth.uid() = user_id);
```

**Team-based access** (shared projects):

```sql
CREATE POLICY "team_select" ON projects FOR SELECT
  USING (
    auth.uid() = owner_id OR
    EXISTS (
      SELECT 1 FROM team_members
      WHERE team_members.project_id = projects.id
        AND team_members.user_id = auth.uid()
    )
  );
```

**Admin override** (service role bypass):

```sql
-- Service role key bypasses RLS by design
-- Never expose service role key to client
```

## Schema conventions

- Table names: `snake_case`, plural (`users`, `blog_posts`)
- Column names: `snake_case` (`created_at`, `user_id`)
- Primary keys: `uuid DEFAULT gen_random_uuid()`
- Timestamps: `timestamptz NOT NULL DEFAULT now()`
- Foreign keys: `{table_singular}_id` naming
- Soft delete: `deleted_at timestamptz` (null = not deleted)
- Enums: `snake_case` (`post_status`, `user_role`)

## Never do these

- Never `select("*")` in production queries
- Never disable RLS on a table with user data
- Never hard delete user-owned rows, soft delete
- Never store passwords in the DB, use Supabase Auth
- Never expose service role key to client
