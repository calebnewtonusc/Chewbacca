# System: Tools, Infrastructure, APIs

**Updated:** When new tools, credentials formats, or infrastructure changes happen.

---

## Claude Code Setup

- **Config:** `~/.claude/settings.json`
- **Project config:** `.claude/settings.json` in each project
- **MCP servers:** See `.mcp.json` in project root
- **Hooks:** PostToolUse auto-formats, auto-syncs context to GitHub, auto-syncs commands to D1-Vibe-Coding

## Key APIs

| Service   | Env Var             | Notes                            |
| --------- | ------------------- | -------------------------------- |
| Anthropic | `ANTHROPIC_API_KEY` | Claude API                       |
| GitHub    | `GITHUB_TOKEN`      | Needs repo + workflow scopes     |
| Todoist   | `TODOIST_API_TOKEN` | For /daily-brief, /sprint, /todo |
| Vercel    | `VERCEL_TOKEN`      | For /deploy                      |

## Deploy Infrastructure

| Project | Platform | URL |
| ------- | -------- | --- |
| ...     | Vercel   | ... |
| ...     | Railway  | ... |

## MCP Servers Active

- **Composio**: GitHub, Gmail, Calendar, Todoist, Vercel, and 100+ more
  - URL: YOUR_COMPOSIO_MCP_URL
  - Get yours at: composio.dev

## Hooks Active

- **UserPromptSubmit:** Injects identity + Todoist priorities into every session
- **PostToolUse (Write/Edit):** Prettier formatting, context sync, D1-Vibe-Coding sync
- **Notification:** `say` command announces task complete
- **SessionStart:** Loads Todoist priorities

## Shell / OS

- OS: macOS
- Shell: zsh
- Key tools: gh, vercel, bun/npm, python3, jq
