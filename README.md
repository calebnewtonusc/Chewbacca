<p align="center">
  <h1 align="center">D1 Vibe Coding</h1>
  <p align="center">The complete Claude Code setup for developers who ship.</p>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://github.com/calebnewtonusc/D1-Vibe-Coding/stargazers"><img src="https://img.shields.io/github/stars/calebnewtonusc/D1-Vibe-Coding?style=social" alt="Stars"></a>
  <a href="https://github.com/calebnewtonusc/D1-Vibe-Coding/commits/main"><img src="https://img.shields.io/github/last-commit/calebnewtonusc/D1-Vibe-Coding" alt="Last Commit"></a>
  <!-- BEGIN GENERATED: badges -->
  <a href=".claude/commands"><img src="https://img.shields.io/badge/slash_commands-36-indigo" alt="Commands"></a>
  <a href=".claude/rules"><img src="https://img.shields.io/badge/always_on_rules-6-green" alt="Rules"></a>
  <a href="docs/EXTENSIONS.md"><img src="https://img.shields.io/badge/plugins-9-orange" alt="Plugins"></a>
  <!-- END GENERATED: badges -->
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
- [Standards Files](#the-standards-files)
- [Verifying the Install](#verifying-the-install)
- [Hooks](#the-hooks)
- [Stack](#stack-assumptions)
- [Ecosystem](#ecosystem-and-resources)
- [Documentation](#documentation)
- [Templates and Snippets](#templates-and-snippets)
- [Skills and Plugins](#skills-and-plugins)
- [Subagents](#subagents)
- [Example Project](#example-project)
- [File Structure](#file-structure)
- [Related Repos](#related-repos)
- [Contributing](#contributing)

---

## What you get

| Feature                | Details                                                                                                                                       |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **36 slash commands**  | Full dev lifecycle: scaffold, push, deploy, audit, PR review, sprint tracking, debugging                                                      |
| **18 standards files** | 6 universal ones imported into every session (~3.7k tokens); 12 stack-specific ones behind a skill that loads only when the work touches them |
| **Full design system** | Dark mode, shadcn/ui, Tailwind, scroll-aware navbar, real typography. Every UI looks like a funded startup's product page                     |
| **Second brain**       | Two-repo system: public `claude-context` (operational) + private `{name}-context` (personal). Auto-syncs to GitHub                            |
| **Smart hooks**        | Format on save, sync context repos, warn on `.env` writes, and flag unpushed work only when there is any                                      |
| **4 subagents**        | context-keeper, code-reviewer, debugger, and explorer, each scoped to one job with its own tool set                                           |
| **Skills and plugins** | graph-engineering and no-ai-slop skills, plus Understand-Anything, context7, serena, and six more plugins                                     |
| **Example project**    | Working Cloudflare Worker + D1 todo app you can deploy in 60 seconds                                                                          |

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
3. Writes `~/.claude/settings.json`, pointing at the hook scripts
4. Installs commands, rules, subagents, and hooks into `~/.claude/`
5. Installs skills, registers both plugin marketplaces, and installs nine plugins
6. Configures Composio MCP if you have a URL
7. Runs `doctor.sh` and refuses to claim success if anything failed

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

## The standards files

Eighteen files, split by whether they earn their place in every session.

**Six always on.** `CLAUDE.md` imports these with `@`, so they are in context
from the first token. About 3,700 tokens total. They apply to any language.

| Rule                   | What it enforces                                                  |
| ---------------------- | ----------------------------------------------------------------- |
| `security.md`          | Parameterized queries, no secrets in logs, ownership checks, SSRF |
| `git.md`               | Commit format, branch naming, stage by filename                   |
| `writing.md`           | Copy standards, no AI slop, no em dashes                          |
| `naming.md`            | File, variable, DB, API, and branch naming conventions            |
| `typescript.md`        | Strict mode patterns, Zod integration, no `any`                   |
| `review-discipline.md` | Code review standards and checklists                              |

**Twelve on demand.** These live in the `stack-rules` skill and load only when
the task touches them: components, api, database, deployment, design,
performance, state, accessibility, scroll-effects, testing, ux-laws, audit.

Importing all eighteen would cost roughly 16,000 tokens on every session,
including a Python service that will never render a component. The skill's
description triggers on UI, API, database, deploy, and test work, so the twelve
arrive exactly when they are relevant and cost nothing otherwise.

## The hooks

Each one is a script in `.claude/hooks/`, installed to `~/.claude/hooks/` and
referenced by path from `settings.json`. They are scripts rather than inline
JSON commands because an inline command with seven levels of backslash escaping
is not something anyone will debug confidently later.

| Hook              | Trigger           | What it does                                                  |
| ----------------- | ----------------- | ------------------------------------------------------------- |
| Session opener    | Every prompt      | Starts every response with a prayer                           |
| `session-context` | Every new session | Loads your context, skipping unfilled template placeholders   |
| `format-and-sync` | After Write/Edit  | Formats with Prettier, then commits and pushes context repos  |
| `stop-check`      | Session end       | Flags uncommitted or unpushed work, silent when there is none |
| `env-guard`       | Before Write      | Warns before writing a real `.env`, ignores `.env.example`    |

**Two defaults to know about before you run `setup.sh`.** Every response opens
with a prayer, and `permissions.defaultMode` is set to `bypassPermissions` so
Claude writes files and runs commands without stopping to confirm. Both are
deliberate: the kit is built around Claude acting rather than asking. Change the
opener text under `hooks.UserPromptSubmit` in `~/.claude/settings.json`, or set
`defaultMode` back to `default` to get the confirmation step. If you are handing
this to someone, tell them both up front.

Three details worth knowing, because each one was silently broken before:

**Prettier needs node on PATH.** Hooks do not inherit an nvm-managed PATH, and
Prettier's shebang is `#!/usr/bin/env node`. Without help it fails to find node
and exits 0, so you get no formatting and no error. `format-and-sync.sh`
resolves the node bin directory itself, and prefers a local or global Prettier
over `npx`, which otherwise re-resolves the package on every single file write.

**The stop reminder is conditional.** An unconditional "push to GitHub" on
every turn is noise, and noise gets ignored. It now checks actual git state and
stays silent when the tree is clean.

**Session context filters placeholders.** Until you fill in `YOU.md`, the
template is empty headings, `- ...` bullets, and `| ... | ... |` rows. Injecting
that is pure token cost, so placeholder lines and headings with no content under
them are dropped.

Hook paths come from `~/.claude/d1-config.sh`, written by `setup.sh`. Edit that
file if you move your context repos.

---

## Verifying the install

```bash
./doctor.sh
```

Every bug this kit shipped in its first six months failed silently. The 18 rules
files installed and nothing loaded them. Prettier could not find node and exited 0. The sync hook swallowed its own git errors. A fresh Mac with no git identity
produced two empty repos and no complaint. In each case you got worse output and
no signal.

`doctor.sh` asserts instead of assuming. It checks the toolchain and git
identity, formats a real file through the hook to prove Prettier works, confirms
every `@` import in CLAUDE.md resolves to a file that exists, verifies each hook
is installed, executable, and emitting valid JSON, and greps the installed
commands and rules for hardcoded credentials. It exits non-zero if anything
fails, and `setup.sh` runs it automatically at the end.

Run it after install, and any time Claude starts behaving like it forgot the
standards.

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

| Doc                                        | What It Covers                                                                                                |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| [docs/METHODOLOGY.md](docs/METHODOLOGY.md) | The five principles of vibe coding, the D1 workflow loop, anti-patterns, measuring effectiveness              |
| [docs/CLOUDFLARE.md](docs/CLOUDFLARE.md)   | D1 query patterns, migrations, Drizzle ORM, Worker routing (vanilla + Hono), D1 + KV + R2, deployment         |
| [docs/PROMPTS.md](docs/PROMPTS.md)         | 20+ real prompts for scaffolding, features, debugging, database work, UI design, deployment                   |
| [docs/INTERNALS.md](docs/INTERNALS.md)     | How Claude Code works under the hood: CLAUDE.md loading, hooks, tools, agents, context compression            |
| [docs/SKILLS.md](docs/SKILLS.md)           | What this kit ships, the four public skill registries, the licensing traps in them, and how to write your own |
| [docs/EXTENSIONS.md](docs/EXTENSIONS.md)   | Skills, plugins, and MCP: what each layer is for, what setup.sh installs, and which to reach for first        |

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

<!-- BEGIN GENERATED: extensions -->

| Extension                                                                           | Layer  | What it does                                                                                   |
| ----------------------------------------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------- |
| [skills/graph-engineering](skills/graph-engineering)                                | Skill  | Knowledge graphs and agent task graphs, with teaching mode                                     |
| [skills/second-brain](skills/second-brain)                                          | Skill  | Reading, writing, and auditing your personal context repo                                      |
| [skills/stack-rules](skills/stack-rules)                                            | Skill  | The 12 stack-specific standards, loaded only when the work needs them                          |
| [avoid-ai-writing](https://github.com/conorbronsdon/avoid-ai-writing)               | Skill  | Audit and rewrite content to remove AI writing patterns ("AI-isms").                           |
| [no-ai-slop](https://github.com/petergyang/no-ai-slop)                              | Skill  | Edit drafts into sharper, more human writing while preserving the writer's personal voice, or… |
| [youtube-transcripts](https://github.com/calebnewtonusc/claude-youtube-transcripts) | Skill  | Get the transcript of a YouTube video, channel, or playlist.                                   |
| [context7](https://github.com/anthropics/claude-plugins-official)                   | Plugin | Real library docs on demand instead of the model's training recall                             |
| [humanizer](https://github.com/blader/humanizer)                                    | Plugin | Strips the Wikipedia-catalogued signs of AI writing out of a draft                             |
| [understand-anything](https://github.com/Egonex-AI/Understand-Anything)             | Plugin | Turns a codebase into an interactive knowledge graph you can query                             |
| bigquery-data-analytics, expo, pinecone, playwright, railway, serena, vercel        | Plugin | Code navigation, browser automation, deploys, and data tooling                                 |
| [prompt-optimizer](https://github.com/linshenkx/prompt-optimizer)                   | MCP    | Rewrites and iterates on prompts through three MCP tools, self-hosted                          |

<!-- END GENERATED: extensions -->

That table is generated. `~/.claude/hooks/sync-to-d1.sh` reads what is actually
installed on the author's machine and rewrites it, along with the install list in
`setup.sh` and the manifest at [settings/toolkit.json](settings/toolkit.json). A
skill reaches this list only if it carries a public upstream URL or ships in this
repo, so a personal skill added locally stays local. MCP servers are opt-in by
name for the same reason.

Full breakdown of which layer to reach for, and why, in [docs/EXTENSIONS.md](docs/EXTENSIONS.md).

---

## Subagents

Four agents in `.claude/agents/`, each with a narrow job and only the tools that
job needs. Claude delegates to them when the task matches; none of them run on
their own.

| Agent            | Use it for                                                                                          |
| ---------------- | --------------------------------------------------------------------------------------------------- |
| `context-keeper` | Auditing and repairing the second brain: contradictions, stale projects, duplicates, relative dates |
| `code-reviewer`  | Reviewing a diff against the standards this kit installs, ranked blocker / should fix / consider    |
| `debugger`       | Tracing a bug to root cause through the seven-step protocol, no guessing                            |
| `explorer`       | Read-only reconnaissance of unfamiliar code, returns conclusions and `file.ts:42` pointers          |

`explorer` cannot write, and `code-reviewer` cannot edit. That is deliberate:
an agent that reports and an agent that changes things should not be the same
agent, or the report starts justifying the changes.

---

## Adding skills from elsewhere

```bash
./add-skill.sh https://github.com/petergyang/no-ai-slop
```

Clones from upstream into `~/.claude/skills/`, carries the LICENSE along, and
records where it came from in a `.source` file so it can be updated later.

It prints the declared license before installing, and warns loudly on
Proprietary or AGPL. That check is not theoretical: one popular skills repo
advertises Apache 2.0 while shipping four skills marked Proprietary and one
under AGPL-3.0, which would relicense an MIT project by contagion.
[docs/SKILLS.md](docs/SKILLS.md) has the full map of what is out there.

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
├── doctor.sh                    # Verifies the install actually works
├── add-skill.sh                 # Installs a skill from upstream, license-aware
├── install.sh                   # Quick project-level install
├── SETUP.md                     # Manual setup instructions
├── .github/                     # Issue templates, PR template, CI
├── .claude/
│   ├── commands/                # 36 slash commands
│   ├── rules/                   # 6 always-on standards, imported by CLAUDE.md
│   ├── hooks/                   # Hook scripts (format, sync, session, stop, env guard)
│   └── agents/                  # 4 subagents (context-keeper, reviewer, debugger, explorer)
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
│   ├── second-brain/            # Operating the personal context repo
│   ├── graph-engineering/       # Knowledge graphs and agent task graphs
│   └── stack-rules/             # 12 stack standards, loaded on demand
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
