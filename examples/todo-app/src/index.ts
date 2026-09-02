/**
 * Todo App: Cloudflare Worker + D1
 *
 * A complete working example demonstrating:
 * - D1 prepared statements (no SQL injection)
 * - CORS middleware
 * - Error handling
 * - Typed environment bindings
 * - CRUD operations with pagination
 * - Batch operations
 *
 * Deploy: wrangler deploy
 * Dev:    wrangler dev
 */

interface Env {
  DB: D1Database;
}

interface Todo {
  id: number;
  title: string;
  completed: number;
  created_at: string;
  updated_at: string;
}

// --- Helpers ---

function json<T>(data: T, status = 200): Response {
  return new Response(JSON.stringify({ data }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function jsonError(message: string, status = 500): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set("Access-Control-Allow-Origin", "*");
  headers.set(
    "Access-Control-Allow-Methods",
    "GET, POST, PUT, PATCH, DELETE, OPTIONS",
  );
  headers.set("Access-Control-Allow-Headers", "Content-Type");
  return new Response(response.body, { status: response.status, headers });
}

// --- Routes ---

async function listTodos(db: D1Database, url: URL): Promise<Response> {
  const page = Math.max(1, parseInt(url.searchParams.get("page") ?? "1", 10));
  const limit = Math.min(
    100,
    Math.max(1, parseInt(url.searchParams.get("limit") ?? "20", 10)),
  );
  const offset = (page - 1) * limit;
  const filter = url.searchParams.get("completed");

  let countSql = "SELECT COUNT(*) as total FROM todos";
  let dataSql = "SELECT * FROM todos";
  const binds: (string | number)[] = [];

  if (filter === "true" || filter === "false") {
    const val = filter === "true" ? 1 : 0;
    countSql += " WHERE completed = ?";
    dataSql += " WHERE completed = ?";
    binds.push(val);
  }

  dataSql += " ORDER BY created_at DESC LIMIT ? OFFSET ?";

  const [countResult, dataResult] = await db.batch([
    db.prepare(countSql).bind(...binds),
    db.prepare(dataSql).bind(...binds, limit, offset),
  ]);

  const total =
    (countResult.results[0] as { total: number } | undefined)?.total ?? 0;

  return new Response(
    JSON.stringify({
      data: dataResult.results,
      meta: { total, page, limit, pages: Math.ceil(total / limit) },
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
}

async function getTodo(db: D1Database, id: number): Promise<Response> {
  const todo = await db
    .prepare("SELECT * FROM todos WHERE id = ?")
    .bind(id)
    .first<Todo>();
  if (!todo) return jsonError("Todo not found", 404);
  return json(todo);
}

async function createTodo(db: D1Database, request: Request): Promise<Response> {
  const body = await request.json<{ title?: string }>().catch(() => null);
  if (
    !body?.title ||
    typeof body.title !== "string" ||
    body.title.trim().length === 0
  ) {
    return jsonError("title is required and must be a non-empty string", 400);
  }

  const todo = await db
    .prepare("INSERT INTO todos (title) VALUES (?) RETURNING *")
    .bind(body.title.trim())
    .first<Todo>();

  return json(todo, 201);
}

async function updateTodo(
  db: D1Database,
  id: number,
  request: Request,
): Promise<Response> {
  const body = await request
    .json<{ title?: string; completed?: boolean }>()
    .catch(() => null);
  if (!body) return jsonError("Invalid request body", 400);

  const sets: string[] = [];
  const values: (string | number)[] = [];

  if (body.title !== undefined) {
    if (typeof body.title !== "string" || body.title.trim().length === 0) {
      return jsonError("title must be a non-empty string", 400);
    }
    sets.push("title = ?");
    values.push(body.title.trim());
  }

  if (body.completed !== undefined) {
    sets.push("completed = ?");
    values.push(body.completed ? 1 : 0);
  }

  if (sets.length === 0) return jsonError("No fields to update", 400);

  values.push(id);
  const todo = await db
    .prepare(`UPDATE todos SET ${sets.join(", ")} WHERE id = ? RETURNING *`)
    .bind(...values)
    .first<Todo>();

  if (!todo) return jsonError("Todo not found", 404);
  return json(todo);
}

async function deleteTodo(db: D1Database, id: number): Promise<Response> {
  const result = await db
    .prepare("DELETE FROM todos WHERE id = ?")
    .bind(id)
    .run();
  if (result.meta.changes === 0) return jsonError("Todo not found", 404);
  return new Response(null, { status: 204 });
}

// --- Router ---

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return withCors(new Response(null, { status: 204 }));
    }

    const url = new URL(request.url);
    const { pathname } = url;
    const method = request.method;

    try {
      // Health
      if (pathname === "/health") {
        const ok = await env.DB.prepare("SELECT 1 as ok").first<{
          ok: number;
        }>();
        return withCors(json({ status: "healthy", db: ok?.ok === 1 }));
      }

      // Root: API info
      if (pathname === "/") {
        return withCors(
          json({
            name: "Todo App (Mac Claude Maxing Example)",
            endpoints: [
              "GET    /health",
              "GET    /api/todos?page=1&limit=20&completed=true|false",
              "POST   /api/todos         { title: string }",
              "GET    /api/todos/:id",
              "PATCH  /api/todos/:id     { title?: string, completed?: boolean }",
              "DELETE /api/todos/:id",
            ],
          }),
        );
      }

      // List / Create
      if (pathname === "/api/todos") {
        if (method === "GET") return withCors(await listTodos(env.DB, url));
        if (method === "POST")
          return withCors(await createTodo(env.DB, request));
        return withCors(jsonError("Method not allowed", 405));
      }

      // Get / Update / Delete by ID
      const match = pathname.match(/^\/api\/todos\/(\d+)$/);
      if (match) {
        const id = parseInt(match[1]!, 10);
        if (method === "GET") return withCors(await getTodo(env.DB, id));
        if (method === "PATCH" || method === "PUT")
          return withCors(await updateTodo(env.DB, id, request));
        if (method === "DELETE") return withCors(await deleteTodo(env.DB, id));
        return withCors(jsonError("Method not allowed", 405));
      }

      return withCors(jsonError("Not found", 404));
    } catch (err) {
      console.error("[Worker Error]", err);
      const message =
        err instanceof Error ? err.message : "Internal server error";
      return withCors(jsonError(message, 500));
    }
  },
} satisfies ExportedHandler<Env>;
