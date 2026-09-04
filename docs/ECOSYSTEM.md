# Vibe Coding Ecosystem

A curated map of the vibe coding landscape: tools, frameworks, awesome lists, and example repos. Organized by category so you can find what you need fast.

---

## Awesome Lists

Curated collections linking to dozens of vibe coding repos, tools, and examples.

| Repo                                                                                                      | Focus                                               |
| --------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| [roboco-io/awesome-vibecoding](https://github.com/roboco-io/awesome-vibecoding)                           | Comprehensive vibe coding resource list             |
| [levz0r/awesome-vibecoded-apps](https://github.com/levz0r/awesome-vibecoded-apps)                         | Curated list of apps built entirely via vibe coding |
| [filipecalegario/awesome-vibe-coding](https://github.com/filipecalegario/awesome-vibe-coding)             | Tools, techniques, and examples                     |
| [ai-for-developers/awesome-vibe-coding](https://github.com/ai-for-developers/awesome-vibe-coding)         | Developer-focused vibe coding resources             |
| [analyticalrohit/awesome-vibe-coding-guide](https://github.com/analyticalrohit/awesome-vibe-coding-guide) | Beginner-friendly guide to vibe coding              |
| [acvnace/awesome-vibe-coding-resources](https://github.com/acvnace/awesome-vibe-coding-resources)         | Resources, tutorials, and templates                 |
| [punkpeye/awesome-mcp-servers](https://github.com/punkpeye/awesome-mcp-servers)                           | MCP servers for AI coding agents                    |

---

## Vibe Coding Platforms and SDKs

Core repos building AI-assisted coding tools and frameworks.

| Repo                                                                                        | What It Does                                                                                                   |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| [cloudflare/vibesdk](https://github.com/cloudflare/vibesdk)                                 | Full-stack vibe coding deployer with D1, Drizzle, Workers. One-click deploy to Cloudflare                      |
| [coleam00/context-engineering-intro](https://github.com/coleam00/context-engineering-intro) | Context engineering templates for Claude Code. How to structure CLAUDE.md and rules for maximum output quality |

---

## Workflow and Orchestration Tools

Repos for AI agent orchestration, settings management, and coding style guides.

| Tool                                                        | What It Does                                                            |
| ----------------------------------------------------------- | ----------------------------------------------------------------------- |
| [cpjet64/vibecoding](https://github.com/cpjet64/vibecoding) | Living repository of vibe coding wisdom, techniques, and best practices |
| Vibe Kanban                                                 | Rust-based AI agent orchestrator for parallel task execution            |
| VibeKit                                                     | Sandboxed AI agent execution environment                                |
| AI Coding Style Guide                                       | Token-efficient prompt compression for faster AI coding                 |

---

## Cloudflare D1 Examples

Directly related to the D1 stack this repo is built around.

| Repo                                                        | What It Does                                                                       |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| [sha256/local-d1](https://github.com/sha256/local-d1)       | Local D1 development replica for Next.js. Run D1 queries locally without deploying |
| [cloudflare/vibesdk](https://github.com/cloudflare/vibesdk) | Reference implementation: Drizzle ORM + D1 + Workers in a vibe coding workflow     |

---

## MCP Servers (Model Context Protocol)

MCP servers extend Claude Code with real-world tool access. These are the ones that matter for vibe coding.

### Official MCP Servers

| Server              | Package                                            | Purpose                               |
| ------------------- | -------------------------------------------------- | ------------------------------------- |
| Filesystem          | `@modelcontextprotocol/server-filesystem`          | Read/write local files directly       |
| GitHub              | `@modelcontextprotocol/server-github`              | Create repos, PRs, issues, read code  |
| Postgres            | `@modelcontextprotocol/server-postgres`            | Query production DB directly          |
| Puppeteer           | `@modelcontextprotocol/server-puppeteer`           | Screenshot URLs, test UI, scrape data |
| Memory              | `@modelcontextprotocol/server-memory`              | Persist facts across sessions         |
| Sequential Thinking | `@modelcontextprotocol/server-sequential-thinking` | Force step-by-step reasoning          |

### Third-Party MCP Servers

| Server       | Purpose                                                            |
| ------------ | ------------------------------------------------------------------ |
| Supabase MCP | `mcp-server-supabase`: manage tables, run migrations, check RLS    |
| Composio MCP | 100+ integrations: GitHub, Gmail, Calendar, Todoist, Vercel, Slack |
| Todoist MCP  | Direct Todoist integration for task management in Claude           |

### Setting Up MCP

MCP config lives at your project root or `~/.claude/`:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/path/to/allowed/dir"
      ]
    },
    "supabase": {
      "command": "npx",
      "args": ["-y", "mcp-server-supabase", "--access-token", "YOUR_TOKEN"]
    }
  }
}
```

See [punkpeye/awesome-mcp-servers](https://github.com/punkpeye/awesome-mcp-servers) for hundreds more.

---

## AI Coding Tools (Beyond Claude Code)

Other tools in the vibe coding space, for reference.

| Tool               | What It Does                                           |
| ------------------ | ------------------------------------------------------ |
| Cursor             | AI-native code editor with inline completions and chat |
| Windsurf (Codeium) | AI coding assistant with deep codebase understanding   |
| Bolt.new           | Browser-based AI app builder, deploys to Cloudflare    |
| v0.dev             | Vercel's AI UI generator, outputs React + Tailwind     |
| Lovable            | AI app builder with full-stack generation              |
| Replit Agent       | AI coding agent inside Replit's cloud IDE              |

---

## Articles and Videos

Key resources for understanding the vibe coding movement.

- [KDnuggets: 10 GitHub Repositories to Master Vibe Coding](https://www.kdnuggets.com/10-github-repositories-to-master-vibe-coding)
- [SashiDo: Master Vibe Coding: Top 10 GitHub Repositories](https://www.sashido.io/en/blog/master-vibe-coding-github-repositories)
- [BetterStack: Cloudflare Vibe SDK Guide](https://betterstack.com/community/guides/ai/cloudflare-vibe-sdk/)
- [MarkTechPost: Cloudflare VibeSDK Open Source](https://www.marktechpost.com/2025/09/23/cloudflare-ai-team-just-open-sourced-vibesdk-that-lets-anyone-build-and-deploy-a-full-ai-vibe-coding-platform-with-a-single-click/)
- [awesome-vibe-coding.com](https://awesome-vibe-coding.com) (web directory)

---

## How to Contribute

Found a repo or tool that belongs here? Open a PR or issue. The criteria:

1. Must be related to AI-assisted development (vibe coding)
2. Must be publicly accessible (open source or public docs)
3. Must be actively maintained (last commit within 6 months)
4. No duplicates of tools already listed

All glory to God!
