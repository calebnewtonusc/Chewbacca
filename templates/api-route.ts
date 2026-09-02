// app/api/{resource}/route.ts: App Router API route template
// Replace {resource} with your actual resource name

import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
// import { createServerClient } from "@supabase/ssr";
// import { cookies } from "next/headers";

// ─── Validation schemas ────────────────────────────────────────────────────

const CreateSchema = z.object({
  name: z.string().min(1).max(255),
  description: z.string().optional(),
});

// ─── GET ───────────────────────────────────────────────────────────────────

export async function GET(req: NextRequest) {
  try {
    // Auth check (uncomment to enable)
    // const supabase = createServerClient(...);
    // const { data: { user } } = await supabase.auth.getUser();
    // if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    const { searchParams } = new URL(req.url);
    const page = Number(searchParams.get("page") ?? "1");
    const limit = Math.min(Number(searchParams.get("limit") ?? "20"), 100);

    // const { data, error, count } = await supabase
    //   .from("items")
    //   .select("id, name, created_at", { count: "exact" })
    //   .order("created_at", { ascending: false })
    //   .range((page - 1) * limit, page * limit - 1);
    //
    // if (error) throw new Error(error.message);

    return NextResponse.json(
      {
        data: [],
        meta: { total: 0, page, perPage: limit },
      },
      { status: 200 },
    );
  } catch (err) {
    console.error("[GET /api/resource]", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}

// ─── POST ──────────────────────────────────────────────────────────────────

export async function POST(req: NextRequest) {
  try {
    // Auth check
    // const supabase = createServerClient(...);
    // const { data: { user } } = await supabase.auth.getUser();
    // if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    // Validate body
    const raw: unknown = await req.json();
    const body = CreateSchema.safeParse(raw);
    if (!body.success) {
      return NextResponse.json(
        { error: "Validation failed", details: body.error.flatten() },
        { status: 400 },
      );
    }

    // const { data, error } = await supabase
    //   .from("items")
    //   .insert({ ...body.data, user_id: user.id })
    //   .select()
    //   .single();
    //
    // if (error) {
    //   if (error.code === "23505") {
    //     return NextResponse.json({ error: "Already exists" }, { status: 409 });
    //   }
    //   throw new Error(error.message);
    // }

    return NextResponse.json({ data: body.data }, { status: 201 });
  } catch (err) {
    console.error("[POST /api/resource]", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}

// ─── DELETE ────────────────────────────────────────────────────────────────

export async function DELETE(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const id = searchParams.get("id");

    if (!id) {
      return NextResponse.json({ error: "Missing id" }, { status: 400 });
    }

    // Auth + ownership check
    // const post = await getItem(id);
    // if (!post) return NextResponse.json({ error: "Not found" }, { status: 404 });
    // if (post.userId !== user.id) return NextResponse.json({ error: "Forbidden" }, { status: 403 });

    // Soft delete: await supabase.from("items").update({ deleted_at: new Date() }).eq("id", id);

    return new NextResponse(null, { status: 204 });
  } catch (err) {
    console.error("[DELETE /api/resource]", err);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}
