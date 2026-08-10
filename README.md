<p align="center">
  <h1 align="center">D1 Vibe Coding</h1>
  <p align="center">The complete Claude Code setup for developers who ship.</p>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://github.com/calebnewtonusc/D1-Vibe-Coding/stargazers"><img src="https://img.shields.io/github/stars/calebnewtonusc/D1-Vibe-Coding?style=social" alt="Stars"></a>
  <a href="https://github.com/calebnewtonusc/D1-Vibe-Coding/commits/main"><img src="https://img.shields.io/github/last-commit/calebnewtonusc/D1-Vibe-Coding" alt="Last Commit"></a>
  <a href=".claude/commands"><img src="https://img.shields.io/badge/slash_commands-36-indigo" alt="Commands"></a>
  <a href=".claude/rules"><img src="https://img.shields.io/badge/rules_files-18-green" alt="Rules"></a>
  <a href="docs/EXTENSIONS.md"><img src="https://img.shields.io/badge/plugins-9-orange" alt="Plugins"></a>
</p>

<p align="center">
  Drop it in and your AI pair programmer immediately writes better code, builds better UIs, and follows consistent patterns.<br>
  One command to wire up your entire development infrastructure: second brain, hooks, MCP, and context sync.
</p>

---

## Table of Contents

- [What You Get](#what-you-get)
- [Quick Start](#quick-start)
- [Full Infrastructure Setup](#full-infrastructure-setup)
- [Slash Commands](#the-slash-commands)
- [Second Brain](#the-second-brain)
- [Design System](#the-design-system)
- [Rules Files](#the-rules-files)
- [Hooks](#the-hooks)
- [Stack](#stack-assumptions)
- [Ecosystem](#ecosystem-and-resources)
- [Documentation](#documentation)
- [Templates and Snippets](#templates-and-snippets)
- [Skills and Plugins](#skills-and-plugins)
- [Example Project](#example-project)
- [File Structure](#file-structure)
- [Related Repos](#related-repos)
- [Contributing](#contributing)

---

## What you get

| Feature                | Details                                                                                                                                                              |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **36 slash commands**  | Full dev lifecycle: scaffold, push, deploy, audit, PR review, sprint tracking, debugging                                                                             |
| **18 rules files**     | Auto-injected context by file type: security, API, components, database, deployment, naming, performance, state, accessibility, TypeScript, design, testing, UX laws |
| **Full design system** | Dark mode, shadcn/ui, Tailwind, scroll-aware navbar, real typography. Every UI looks like a funded startup's product page                                            |
| **Second brain**       | Two-repo system: public `claude-context` (operational) + private `{name}-context` (personal). Auto-syncs to GitHub                                                   |
| **Smart hooks**        | Auto-format on save, sync context repos, warn on `.env` writes, load Todoist priorities at session start                                                             |
| **iMessage agent**     | Optional macOS integration: read chat history, triage messages, send via AppleScript                                                                                 |
| **Skills and plugins** | graph-engineering and no-ai-slop skills, plus Understand-Anything, context7, serena, and six more plugins |
| **Example project**    | Working Cloudflare Worker + D1 todo app you can deploy in 60 seconds                                                                                                 |

---

## Quick Start

**Option A: Just want CLAUDE.md + commands + rules in an existing project:**

```bash
curl -fsSL https://raw.githubusercontent.com/calebnewtonusc/D1-Vibe-Coding/main/install.sh | bash
```

**Option B: Want the full quick-start CLAUDE.md (50 lines, essential patterns only):**

```bash
curl -fsSL https://raw.githubusercontent.com/calebnewtonusc/D1-Vibe-Coding/main/CLAUDE-QUICK.md > CLAUDE.md
```

**Option C: Want everything (second brain, hooks, MCP, full context system):**

```bash
git clone https://github.com/calebnewtonusc/D1-Vibe-Coding
cd D1-Vibe-Coding
chmod +x setup.sh && ./setup.sh
```

---

## Full infrastructure setup

The `setup.sh` script collects your name, GitHub username, and API keys, then:

1. Creates `{your-name}-context` (private GitHub repo) with personal brain templates
2. Creates `claude-context` (public GitHub repo) with operational instructions
3. Optionally sets up the iMessage agent (macOS only)
4. Writes `~/.claude/settings.json` with all hooks
5. Installs commands and rules globally to `~/.claude/`
6. Installs skills, registers both plugin marketplaces, and installs nine plugins
7. Configures Composio MCP if you have a URL

You end up with a fully wired Claude setup. Every session starts with your full context loaded. Every edit to your context files auto-commits and auto-pushes.

---

## The slash commands

| Command           | What it does                                                   |
| ----------------- | -------------------------------------------------------------- |
| `/new-project`    | Scaffold Next.js + shadcn/ui + Tailwind + all deps in one shot |
| `/push`           | Secret scan, smart commit message, push                        |
| `/deploy`         | Quality gate + Vercel deploy                                   |
| `/ship`           | Typecheck + lint + tests before any merge                      |
| `/audit`          | Security scan + code quality + design quality                  |
| `/pr-shepherd`    | Full PR lifecycle: review, fix, CI, merge                      |
| `/respond-pr`     | Read all review comments, implement fixes, reply with SHAs     |
| `/fix-issue`      | Fetch GitHub issue, branch, research, implement, commit        |
| `/review-pr`      | Deep code review with inline comments                          |
| `/review`         | Review current file or selection                               |
| `/review-project` | Deep audit a project: bugs, incomplete work, security issues   |
| `/triage-issues`  | Classify issues, score severity, detect duplicates, prioritize |
| `/triage-prs`     | PR dashboard by module, review state, scope, and risk          |
| `/daily-brief`    | Today's tasks + GitHub PRs + focused plan                      |
| `/morning`        | Morning standup: yesterday, today, blockers                    |
| `/close-loop`     | End-of-session: commit, push, log, set up tomorrow             |
| `/standup`        | Generate standup from git log                                  |
| `/changelog`      | Changelog from git log since last tag                          |
| `/cleanup`        | Remove dead code, console.logs, unused imports                 |
| `/deps`           | Check outdated, unused, vulnerable dependencies                |
| `/env-check`      | Compare `.env.example` vs `.env` to find gaps                  |
| `/sprint`         | Today's task breakdown by priority                             |
| `/todo`           | Add a task from natural language                               |
| `/done`           | Mark a task complete                                           |
| `/inbox`          | Process all open tasks + emails + PRs                          |
| `/build`          | Run build checks and fix errors                                |
| `/test`           | Write or run tests for the current feature                     |
| `/debug`          | Systematic debug protocol: read error, trace, fix              |
| `/trace`          | Trace a bug to its root cause                                  |
| `/refactor`       | Refactor selected code cleanly                                 |
| `/design`         | Design review against the D1 design system                     |
| `/api`            | Scaffold a new API route with validation                       |
| `/database`       | Scaffold migration, types, and query functions                 |
| `/context-update` | Manually trigger context file sync                             |
| `/scratchpad`     | Capture quick ideas                                            |
| `/imovie`         | AirDrop-to-iMovie automation (macOS)                           |

---

## The second brain

Two repos. Hard boundary between operational and personal.

```
claude-context/      PUBLIC: how Claude should behave
                     CLAUDE.md, rules/, commands/, hooks/
                     Zero personal info. Safe to share.

{name}-context/      PRIVATE: who you are and what you're working on
                     YOU.md, NOW.md, PEOPLE.md, SYSTEM.md, STACK.md
                     Never make this public.
```

Claude loads your personal context every session via the `SessionStart` hook. Every time Claude writes to a context file, the `PostToolUse` hook auto-commits and auto-pushes. Your brain stays current without you touching it.

See [second-brain/README.md](second-brain/README.md) for full architecture details.

---

## The design system

The `CLAUDE.md` is the core. It enforces:

- **Dark mode by default**: `#0a0a0a` background, `zinc-950` surfaces
- **shadcn/ui always**: never raw `<button>` or `<input>` from scratch
- **Lucide React icons**: never emoji, never text characters as icons
- **Scroll-aware navbar**: hidden at top, slides in after 80px, hides near page bottom
- **Typography hierarchy**: Inter/Geist, `text-5xl font-bold tracking-tight` heroes, proper scale
- **Cards and buttons with hover states**: every interactive element
- **Loading/empty/error states**: never blank white space
- **Responsive layouts**: mobile-first, `max-w-7xl` containers

Before shipping any UI, ask: does this look like a YC-backed startup's product page? If not, rebuild it.

New to this? Start with [CLAUDE-QUICK.md](CLAUDE-QUICK.md) (50 lines, essential patterns only).

---

## The rules files

Each file is auto-loaded as context when Claude touches matching files:

| Rule                   | What It Enforces                                                      |
| ---------------------- | --------------------------------------------------------------------- |
| `security.md`          | Parameterized queries, RLS, no secrets in logs, auth ownership checks |
| `api.md`               | Next.js App Router routes, Zod validation, consistent error shapes    |
| `components.md`        | shadcn/ui enforcement, skeleton/empty/error state patterns            |
| `database.md`          | Supabase conventions, RLS policies, migration workflow                |
| `deployment.md`        | Vercel deploy workflow, pre-deploy checklist                          |
| `naming.md`            | File, variable, DB, API, branch naming conventions                    |
| `performance.md`       | `next/image`, `next/font`, Server Components, bundle size             |
| `state.md`             | React Query for server state, URL state, Zustand for shared UI        |
| `accessibility.md`     | Semantic HTML, focus management, WCAG contrast, ARIA                  |
| `typescript.md`        | Strict mode patterns, Zod integration, no `any`                       |
| `design.md`            | D1 design system: color, typography, components                       |
| `writing.md`           | Copy standards, no AI slop                                            |
| `scroll-effects.md`    | CSS scroll animations, IntersectionObserver, parallax                 |
| `testing.md`           | Unit, integration, and E2E testing patterns                           |
| `ux-laws.md`           | Hick's, Fitts's, Miller's, and other UX laws applied                  |
| `review-discipline.md` | Code review standards and checklists                                  |
| `audit.md`             | Pre-ship audit checklist                                              |
| `git.md`               | Commit format, branch naming, PR rules                                |

---

## The hooks

| Hook           | Trigger           | What It Does                                             |
| -------------- | ----------------- | -------------------------------------------------------- |
| `SessionStart` | Every new session | Load personal context + Todoist priorities               |
| `PostToolUse`  | After Write/Edit  | Auto-format with Prettier + sync context repos to GitHub |
| `PreToolUse`   | Before Write      | Warn before touching `.env` files                        |
| `Stop`         | Session end       | Remind to push to GitHub + surface TODOs                 |
| `Notification` | Task complete     | Voice alert via macOS `say`                              |

The `PostToolUse` hook watches your `{name}-context/` and `claude-context/` directories. Any write auto-commits and pushes.

---

## Stack assumptions

This kit is optimized for:

- **Next.js 14+** (App Router)
- **Tailwind CSS** + **shadcn/ui**
- **Supabase** (auth + database)
- **Vercel** (deployment)
- **TypeScript** (strict mode)
- **GitHub** (via `gh` CLI)
- **Anthropic Claude** (`claude-opus-5` default)

---

## Ecosystem and resources

The vibe coding landscape is growing fast. **[ECOSYSTEM.md](ECOSYSTEM.md)** is our curated map:

- 7 awesome lists aggregating hundreds of vibe-coded projects
- Vibe coding platforms and SDKs (VibeSDK, context engineering templates)
- Workflow and orchestration tools
- Cloudflare D1 example repos
- MCP server directory (official + third-party)
- AI coding tools beyond Claude Code
- Articles and videos

---

## Documentation

| Doc                                        | What It Covers                                                                                         |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------ |
| [docs/METHODOLOGY.md](docs/METHODOLOGY.md) | The five principles of vibe coding, the D1 workflow loop, anti-patterns, measuring effectiveness       |
| [docs/CLOUDFLARE.md](docs/CLOUDFLARE.md)   | D1 query patterns, migrations, Drizzle ORM, Worker routing (vanilla + Hono), D1 + KV + R2, deployment  |
| [docs/PROMPTS.md](docs/PROMPTS.md)         | 20+ real prompts for scaffolding, features, debugging, database work, UI design, deployment            |
| [docs/INTERNALS.md](docs/INTERNALS.md)     | How Claude Code works under the hood: CLAUDE.md loading, hooks, tools, agents, context compression     |
| [docs/EXTENSIONS.md](docs/EXTENSIONS.md)   | Skills, plugins, and MCP: what each layer is for, what setup.sh installs, and which to reach for first |

---

## Templates and snippets

### Templates (full starter files)

| File                                                             | What It Is                                                                 |
| ---------------------------------------------------------------- | -------------------------------------------------------------------------- |
| [templates/cloudflare-worker.ts](templates/cloudflare-worker.ts) | Complete Worker + D1 entry point with CORS, error handling, JSON helpers   |
| [templates/d1-migration.sql](templates/d1-migration.sql)         | Migration template with standard columns, indexes, and auto-update trigger |
| [templates/hero.tsx](templates/hero.tsx)                         | Hero section with gradient text and CTA buttons                            |
| [templates/navbar.tsx](templates/navbar.tsx)                     | Scroll-aware navbar                                                        |
| [templates/card.tsx](templates/card.tsx)                         | Dark mode card with hover states                                           |
| [templates/api-route.ts](templates/api-route.ts)                 | Next.js API route with Zod validation                                      |
| [templates/page.tsx](templates/page.tsx)                         | Page with loading/error/empty states                                       |
| [templates/globals.css](templates/globals.css)                   | Tailwind globals with dark mode                                            |
| [templates/loading.tsx](templates/loading.tsx)                   | Skeleton loader                                                            |
| [templates/error.tsx](templates/error.tsx)                       | Error boundary                                                             |
| [templates/not-found.tsx](templates/not-found.tsx)               | 404 page                                                                   |

### Snippets (copy-paste patterns)

| File                                                       | What It Is                                         |
| ---------------------------------------------------------- | -------------------------------------------------- |
| [snippets/drizzle-d1.ts](snippets/drizzle-d1.ts)           | Drizzle ORM + D1 schema, types, and query examples |
| [snippets/wrangler.toml](snippets/wrangler.toml)           | Annotated wrangler config with all binding types   |
| [snippets/useScrollNav.tsx](snippets/useScrollNav.tsx)     | Scroll-aware navbar hook                           |
| [snippets/tailwind.config.ts](snippets/tailwind.config.ts) | Tailwind config with custom theme                  |
| [snippets/prettierrc.json](snippets/prettierrc.json)       | Prettier config                                    |
| [snippets/gitignore.txt](snippets/gitignore.txt)           | Standard .gitignore                                |

---

## Skills and plugins

Rules and commands are only part of the setup now. Skills load deep domain knowledge on demand, so a
40KB reference costs nothing until the task calls for it. Plugins bundle skills, MCP servers, and
subagents behind one versioned install.

`setup.sh` installs all of it. What you get:

| Extension                                                                    | Layer  | What it does                                                          |
| ---------------------------------------------------------------------------- | ------ | --------------------------------------------------------------------- |
| [skills/graph-engineering](skills/graph-engineering)                         | Skill  | Knowledge graphs and agent task graphs, with teaching mode            |
| [no-ai-slop](https://github.com/petergyang/no-ai-slop)                       | Skill  | Strips 20+ AI-slop patterns from a draft, or flags them without edits |
| [Understand-Anything](https://github.com/Egonex-AI/Understand-Anything)      | Plugin | Turns a codebase into an interactive knowledge graph you can query    |
| [context7](https://github.com/anthropics/claude-plugins-official)            | Plugin | Real library docs on demand instead of the model's training recall    |
| serena, playwright, vercel, railway, expo, pinecone, bigquery-data-analytics | Plugin | Code navigation, browser automation, deploys, and data tooling        |

Full breakdown of which layer to reach for, and why, in [docs/EXTENSIONS.md](docs/EXTENSIONS.md).

---

## Example project

A working Cloudflare Worker + D1 todo API you can deploy in 60 seconds:

```bash
cd examples/todo-app
npm install
wrangler d1 create todo-db
# Copy the database_id into wrangler.toml
wrangler d1 migrations apply todo-db --local
wrangler dev
```

Then hit `http://localhost:8787/api/todos` to see it running.

See [examples/todo-app/README.md](examples/todo-app/README.md) for full details.

---

## File structure

```
D1-Vibe-Coding/
├── CLAUDE.md                    # Full design system (700 lines)
├── CLAUDE-QUICK.md              # Quick-start version (50 lines)
├── ECOSYSTEM.md                 # Curated vibe coding landscape map
├── CONTRIBUTING.md              # How to contribute
├── LICENSE                      # MIT
├── setup.sh                     # One-command full infrastructure setup
├── install.sh                   # Quick project-level install
├── SETUP.md                     # Manual setup instructions
├── .github/                     # Issue templates, PR template, CI
├── .claude/
│   ├── commands/                # 36 slash commands
│   ├── rules/                   # 18 rules files (auto-injected context)
│   └── hooks/                   # PostToolUse formatters and sync hooks
├── docs/
│   ├── METHODOLOGY.md           # Vibe coding philosophy and workflow
│   ├── CLOUDFLARE.md            # D1/Workers/KV/R2 patterns and examples
│   ├── PROMPTS.md               # Example AI prompts for every stage of dev
│   ├── INTERNALS.md             # How Claude Code works under the hood
│   └── EXTENSIONS.md            # Skills, plugins, MCP: which layer to reach for
├── examples/
│   └── todo-app/                # Working Worker + D1 example (deploy in 60s)
├── templates/                   # Full starter files (Worker, migration, components)
├── snippets/                    # Copy-paste patterns (Drizzle, wrangler, hooks)
├── skills/
│   └── graph-engineering/       # Knowledge graphs and agent task graphs
├── second-brain/
│   ├── README.md                # Two-repo architecture explained
│   ├── init-brain.sh            # Standalone second brain setup
│   ├── context/                 # Personal context templates
│   └── agents/                  # iMessage, Composio, Todoist guides
└── settings/
    ├── settings.json            # Hooks + permissions template
    └── README.md                # How to configure
```

---

## Related repos

| Repo                                                                                        | What It Is                                              |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| [cloudflare/vibesdk](https://github.com/cloudflare/vibesdk)                                 | Cloudflare's official vibe coding SDK with D1 + Drizzle |
| [coleam00/context-engineering-intro](https://github.com/coleam00/context-engineering-intro) | Context engineering templates for Claude Code           |
| [roboco-io/awesome-vibecoding](https://github.com/roboco-io/awesome-vibecoding)             | The biggest awesome list for vibe coding                |
| [punkpeye/awesome-mcp-servers](https://github.com/punkpeye/awesome-mcp-servers)             | Directory of MCP servers for AI agents                  |
| [sha256/local-d1](https://github.com/sha256/local-d1)                                       | Local D1 dev replica for Next.js                        |
| [cpjet64/vibecoding](https://github.com/cpjet64/vibecoding)                                 | Vibe coding techniques and wisdom                       |

See [ECOSYSTEM.md](ECOSYSTEM.md) for the full list.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). PRs welcome. The bar: does this work for every developer, not just one person?

---

Built by [Caleb Newton](https://github.com/calebnewtonusc)

All glory to God!
