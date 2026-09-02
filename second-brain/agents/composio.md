# Composio MCP Integration

Composio gives Claude access to 100+ tools via a single MCP server: GitHub, Gmail, Google Calendar, Todoist, Vercel, Linear, Slack, Notion, and more. One setup, everything connected.

## What you get

| Category | Tools                                            |
| -------- | ------------------------------------------------ |
| Code     | GitHub (create repos, PRs, issues, read code)    |
| Email    | Gmail (read, send, search, draft)                |
| Calendar | Google Calendar (events, free slots, scheduling) |
| Tasks    | Todoist (create, complete, list tasks)           |
| Deploy   | Vercel (deployments, projects, env vars)         |
| Docs     | Google Docs, Sheets, Drive                       |

## Setup

### 1. Create a Composio account

Go to [composio.dev](https://composio.dev) and sign up. Free tier covers the essentials.

### 2. Get your MCP URL

In your Composio dashboard, navigate to MCP Servers and copy your personal MCP URL. It looks like:

```
https://backend.composio.dev/v3/mcp/YOUR_ID/mcp?user_id=YOUR_USER_ID
```

### 3. Add to .mcp.json

Create or update `.mcp.json` in your project root:

```json
{
  "mcpServers": {
    "composio": {
      "url": "YOUR_COMPOSIO_MCP_URL",
      "headers": {
        "x-api-key": "YOUR_COMPOSIO_API_KEY"
      }
    }
  }
}
```

Your API key is in your Composio dashboard under Settings → API Keys.

### 4. Connect your apps

In the Composio dashboard, connect the services you want:

- Click "Add Integration"
- Select the app (GitHub, Gmail, etc.)
- Authorize via OAuth or API key
- Done: Claude can now use it

### 5. Test it

In a Claude Code session:

```
List my open GitHub PRs across all repos
```

```
What's on my calendar tomorrow?
```

```
Send an email to X@gmail.com with subject "Hello" and body "Testing Composio"
```

## Adding to session context

Once Composio is connected, the SessionStart hook can inject Todoist priorities automatically. Add to `~/.claude/settings.json`:

```json
"SessionStart": [{
  "hooks": [{
    "type": "command",
    "command": "TASKS=$(curl -sf 'https://api.todoist.com/rest/v2/tasks?filter=today' -H 'Authorization: Bearer YOUR_TODOIST_TOKEN' | python3 -c \"import json,sys; tasks=json.load(sys.stdin); top=[t['content'] for t in sorted(tasks, key=lambda x: -x.get('priority',1))[:3]]; print(', '.join(top))\" 2>/dev/null || echo 'none'); printf '%s' \"{\\\"hookSpecificOutput\\\": {\\\"hookEventName\\\": \\\"SessionStart\\\", \\\"additionalContext\\\": \\\"Today priorities: $TASKS\\\"}}\"",
    "statusMessage": "Loading Todoist..."
  }]
}]
```

## Security

Your Composio MCP URL is a credential, treat it like an API key:

- Never commit it to a public repo
- Store it in `~/.claude/settings.json` (not in project-level `.mcp.json` if the project is public)
- Rotate it from the Composio dashboard if exposed
