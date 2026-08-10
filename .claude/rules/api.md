# API Rules

## Always Use Next.js App Router API Routes

Structure: `app/api/{resource}/route.ts`

```ts
import { NextRequest, NextResponse } from "next/server";

export async function GET(req: NextRequest) {
  try {
    // logic
    return NextResponse.json({ data }, { status: 200 });
  } catch (err) {
    console.error("[GET /api/resource]", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}
```

## Validation: Always Use Zod

Never trust `req.body` or `req.json()` raw. Parse and validate with Zod:

```ts
import { z } from "zod";

const schema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
});

const body = schema.safeParse(await req.json());
if (!body.success) {
  return NextResponse.json({ error: body.error.flatten() }, { status: 400 });
}
```

## Error Response Format

Always return consistent error shapes:

```ts
// Success
{ data: T, meta?: { total, page, perPage } }

// Error
{ error: string, details?: unknown }
```

## HTTP Status Codes

- `200` OK (GET/PATCH success)
- `201` Created (POST that creates a resource)
- `204` No Content (DELETE success)
- `400` Bad Request (validation failure)
- `401` Unauthorized (not authenticated)
- `403` Forbidden (authenticated but not allowed)
- `404` Not Found
- `409` Conflict (duplicate)
- `500` Internal Server Error

## Authentication

Use Supabase server client for auth in API routes:

```ts
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

const {
  data: { user },
} = await supabase.auth.getUser();
if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
```

## Anthropic API Integration

Default model: `claude-opus-5`. Cheaper high-volume: `claude-sonnet-5`. Fast/cheap: `claude-haiku-4-5`.

Use `output_config: { effort: "high" }` to tune depth. `temperature`, `top_p`, and `budget_tokens` are rejected on Opus 5 and return a 400.

```ts
import Anthropic from "@anthropic-ai/sdk";

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const message = await client.messages.create({
  model: "claude-opus-5",
  max_tokens: 1024,
  messages: [{ role: "user", content: prompt }],
});
```

## Streaming Responses

```ts
const stream = await client.messages.stream({ model: "claude-opus-5", ... });

return new Response(stream.toReadableStream(), {
  headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
});
```

## Environment Variables

- Never hardcode secrets — always `process.env.VAR_NAME`
- Client-safe vars: prefix `NEXT_PUBLIC_`
- Always add to `.env.example` with placeholder values
- Never commit `.env`

## Never Do These

- Never expose internal error stack traces in production responses
- Never log raw request bodies containing passwords or tokens
- Never use `any` type in route handlers
- Never skip validation on user-provided input
