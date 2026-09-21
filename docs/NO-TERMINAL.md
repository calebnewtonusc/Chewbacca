# Using the kit without a terminal

The honest state, then how to get the part that works.

## Why this document exists

Everything else in this kit is delivered as a `SKILL.md` read off the
filesystem, a hook in a process lifecycle, or a command-line tool. All three
need a shell. So the answer to "can somebody use this from Claude or ChatGPT
in a browser" was **zero percent**, not partially: a browser client has no
filesystem and no shell, and there was no subset that worked.

Sagar Tiwari, a technical co-founder, tried the terminal install twice on
2026-09-19 and 09-20 and stopped at *"it's not a product I need to work for
me."* That is the bar this fails, and it fails it for a reason that is
structural rather than cosmetic.

`bin/chewbacca-mcp` is the first surface that does not need a shell. The kit
already consumed twelve MCP servers and had never exposed itself as one, so
its own most valuable data was the least reachable thing on the machine.

## What it gives you

Five read-only tools. No writes: a browser client reaching into a laptop is
exactly the wrong place to expose one, and everything valuable here is a
question anyway.

| Tool | Answers |
| --- | --- |
| `who_do_i_know` | "do I know anyone at X", "who works in Y" |
| `person_brief` | everything recorded about one person |
| `who_am_i_overdue_with` | who you have not contacted in longer than your own cadence |
| `whats_due` | real deadlines from your syllabus ledger |
| `course_ai_policy` | what a course allows regarding AI help |

## Claude Desktop or Claude Code

```json
{
  "mcpServers": {
    "chewbacca": { "command": "/Users/YOU/.local/bin/chewbacca-mcp" }
  }
}
```

## A browser client that accepts a URL

```
chewbacca-mcp --http 7788
```

Then point the connector at `http://127.0.0.1:7788`.

**It binds to 127.0.0.1 and nothing else.** This serves an entire relationship
history and message archive; binding to `0.0.0.0` would publish that to the
local network, and on campus wifi that is the whole building.

## What this still does not fix

This is one step, not the destination. Still true:

- **It requires the terminal once**, to install. The tool has to exist on disk
  before a browser can reach it, and there is no signed `.app` yet
- **It is macOS only.** The data it reads lives in macOS databases
- **No authentication on the HTTP transport.** Localhost-only is the entire
  boundary. Any local process can call it
- **Five tools, not the whole kit.** The crafts, the writing rules, the HUD
  and the Mac automation are all still shell-shaped

The unit of distribution is still a git clone. Until that changes, "my grandma
could click one button" is not true, and this document exists so nobody claims
otherwise from the presence of an MCP server.
