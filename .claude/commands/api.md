---
description: Build a full Next.js API route — Zod validation, auth, error handling, TypeScript
allowed-tools: Bash(npm:*), Bash(npx:*), Read, Write, Edit, Glob
argument-hint: "<resource description — e.g. 'POST /api/projects, creates a new project for the authenticated user'>"
---

# API

Build the API route for `$ARGUMENTS`. Zod validation, auth check, proper HTTP codes, full types.

## Step 1: Parse the route spec

From `$ARGUMENTS`, extract:

- **HTTP method(s)**: GET, POST, PATCH, DELETE
- **Resource**: what entity is being operated on
- **Auth requirement**: authenticated? public?
- **Input**: what does the request body / query params contain?
- **Output**: what does the response return?

## Step 2: Create the route file

Path: `src/app/api/{resource}/route.ts`

For nested resources: `src/app/api/{parent}/{[id]}/{resource}/route.ts`

## Step 3: Write the route

### GET: list or fetch

```typescript
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import type { Database } from "@/types/supabase";

// Query param schema (optional)
const querySchema = z.object({
  page: z.coerce.number().min(1).default(1),
  limit: z.coerce.number().min(1).max(100).default(20),
  status: z.enum(["active", "archived"]).optional(),
});

export async function GET(req: NextRequest): Promise<NextResponse> {
  try {
    // 1. Auth
    const cookieStore = await cookies();
    const supabase = createServerClient<Database>(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
    );
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    // 2. Validate query params
    const params = querySchema.safeParse(
      Object.fromEntries(req.nextUrl.searchParams),
    );
    if (!params.success) {
      return NextResponse.json(
        { error: params.error.flatten() },
        { status: 400 },
      );
    }
    const { page, limit, status } = params.data;
    const offset = (page - 1) * limit;

    // 3. Query — specific columns, never select("*")
    let query = supabase
      .from("{resource}")
      .select("id, name, description, status, created_at", { count: "exact" })
      .eq("user_id", user.id)
      .is("deleted_at", null)
      .order("created_at", { ascending: false })
      .range(offset, offset + limit - 1);

    if (status) query = query.eq("status", status);

    const { data, error, count } = await query;
    if (error) throw new Error(error.message);

    return NextResponse.json(
      {
        data,
        meta: { total: count ?? 0, page, limit },
      },
      { status: 200 },
    );
  } catch (err) {
    console.error("[GET /api/{resource}]", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}
```

### POST: create

```typescript
const createSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().max(2000).optional(),
});

export async function POST(req: NextRequest): Promise<NextResponse> {
  try {
    // 1. Auth
    const cookieStore = await cookies();
    const supabase = createServerClient<Database>(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
    );
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    // 2. Validate body
    const body = createSchema.safeParse(await req.json());
    if (!body.success) {
      return NextResponse.json(
        { error: body.error.flatten() },
        { status: 400 },
      );
    }

    // 3. Check for duplicates (if applicable)
    const { data: existing } = await supabase
      .from("{resource}")
      .select("id")
      .eq("user_id", user.id)
      .eq("name", body.data.name)
      .is("deleted_at", null)
      .single();
    if (existing) {
      return NextResponse.json(
        { error: "A {resource} with this name already exists" },
        { status: 409 },
      );
    }

    // 4. Insert
    const { data, error } = await supabase
      .from("{resource}")
      .insert({ ...body.data, user_id: user.id })
      .select("id, name, description, status, created_at")
      .single();
    if (error) throw new Error(error.message);

    return NextResponse.json({ data }, { status: 201 });
  } catch (err) {
    console.error("[POST /api/{resource}]", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}
```

### PATCH: update (by [id])

Path: `src/app/api/{resource}/[id]/route.ts`

```typescript
const updateSchema = z
  .object({
    name: z.string().min(1).max(255).optional(),
    description: z.string().max(2000).optional(),
    status: z.enum(["active", "archived"]).optional(),
  })
  .refine((data) => Object.keys(data).length > 0, {
    message: "At least one field must be provided",
  });

export async function PATCH(
  req: NextRequest,
  { params }: { params: { id: string } },
): Promise<NextResponse> {
  try {
    const cookieStore = await cookies();
    const supabase = createServerClient<Database>(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
    );
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const body = updateSchema.safeParse(await req.json());
    if (!body.success) {
      return NextResponse.json(
        { error: body.error.flatten() },
        { status: 400 },
      );
    }

    // RLS handles ownership — if this returns null, user doesn't own it
    const { data, error } = await supabase
      .from("{resource}")
      .update(body.data)
      .eq("id", params.id)
      .select("id, name, description, status, updated_at")
      .single();

    if (error || !data) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }

    return NextResponse.json({ data }, { status: 200 });
  } catch (err) {
    console.error("[PATCH /api/{resource}/[id]]", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}
```

### DELETE: soft delete

```typescript
export async function DELETE(
  req: NextRequest,
  { params }: { params: { id: string } },
): Promise<NextResponse> {
  try {
    const cookieStore = await cookies();
    const supabase = createServerClient<Database>(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
    );
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    // Soft delete — never hard delete user data
    const { error } = await supabase
      .from("{resource}")
      .update({ deleted_at: new Date().toISOString(), status: "deleted" })
      .eq("id", params.id);

    if (error) {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }

    return new NextResponse(null, { status: 204 });
  } catch (err) {
    console.error("[DELETE /api/{resource}/[id]]", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}
```

## Step 4: TypeScript check

```bash
npx tsc --noEmit 2>&1 | grep "route.ts"
```

Zero errors required.

## Step 5: Document the route

Add to `src/app/api/README.md` (create if missing):

```markdown
## {METHOD} /api/{resource}

**Auth**: Required (Supabase JWT)

**Request**:
\`\`\`json
{ "name": "string", "description": "string?" }
\`\`\`

**Response 201**:
\`\`\`json
{ "data": { "id": "uuid", "name": "string", ... } }
\`\`\`

**Errors**:

- 400: Validation failed (`{ error: { fieldErrors: {...} } }`)
- 401: Not authenticated
- 409: Duplicate name
- 500: Internal error
```

## HTTP status code reference

| Code | When                                |
| ---- | ----------------------------------- |
| 200  | GET / PATCH success                 |
| 201  | POST created a resource             |
| 204  | DELETE success (no body)            |
| 400  | Validation failed                   |
| 401  | Not authenticated                   |
| 403  | Authenticated but not allowed       |
| 404  | Resource not found (or RLS blocked) |
| 409  | Conflict (duplicate)                |
| 500  | Unexpected server error             |

## Never do these

- Never `req.json()` without Zod validation
- Never `select("*")` — always specific columns
- Never expose stack traces in error responses
- Never trust `params.id` for ownership — let RLS handle it or check explicitly
- Never return 404 for auth failures — use 401/403 (prevents enumeration)
- Never skip the auth check on any route that touches user data
