# AI features

Loads when the work involves an LLM: an agent, a chat surface, a generation
endpoint, an eval harness. Most sessions are not building an AI feature and
were carrying this anyway.

## AI FEATURES: ALWAYS USE VERCEL AI SDK

For any feature involving AI responses, streaming, or structured outputs:

### Streaming responses (mandatory: never buffer AI output)

```typescript
import { streamText } from "ai";
import { anthropic } from "@ai-sdk/anthropic";

export async function POST(req: Request) {
  const { messages } = await req.json();
  const result = streamText({
    model: anthropic("claude-opus-5"),
    messages,
    system: "You are a helpful assistant.",
  });
  return result.toDataStreamResponse();
}
```

### Client-side streaming hook

```typescript
import { useChat } from "ai/react";

export function ChatUI() {
  const { messages, input, handleInputChange, handleSubmit, isLoading } =
    useChat({
      api: "/api/chat",
    });
  // render messages
}
```

### Structured outputs (use when you need typed JSON back)

```typescript
import { generateObject } from "ai";
import { z } from "zod";

const { object } = await generateObject({
  model: anthropic("claude-opus-5"),
  schema: z.object({
    title: z.string(),
    tags: z.array(z.string()),
    priority: z.enum(["low", "medium", "high"]),
  }),
  prompt: "Analyze this task and categorize it.",
});
// object is fully typed
```

### Tool calling (give Claude real-world actions)

```typescript
import { streamText, tool } from "ai";
import { z } from "zod";

const result = streamText({
  model: anthropic("claude-opus-5"),
  tools: {
    searchDatabase: tool({
      description: "Search the product database",
      parameters: z.object({ query: z.string() }),
      execute: async ({ query }) => searchProducts(query),
    }),
  },
  messages,
});
```

### RAG architecture basics

1. **Ingest**: chunk documents → embed with `text-embedding-3-small` → store in Supabase `pgvector`
2. **Retrieve**: embed user query → cosine similarity search → return top K chunks
3. **Generate**: inject chunks into system prompt → stream response

---
