<p align="center">
  <h1 align="center">Chewbacca</h1>
  <p align="center">Turns Claude into the world's best sidekick. Nothing to remember, nothing to type.</p>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://github.com/calebnewtonusc/Chewbacca/stargazers"><img src="https://img.shields.io/github/stars/calebnewtonusc/Chewbacca?style=social" alt="Stars"></a>
  <a href="https://github.com/calebnewtonusc/Chewbacca/commits/main"><img src="https://img.shields.io/github/last-commit/calebnewtonusc/Chewbacca" alt="Last Commit"></a>
<!-- BEGIN GENERATED: badges -->
  <a href=".claude/commands"><img src="https://img.shields.io/badge/slash_commands-48-indigo" alt="Commands"></a>
  <a href=".claude/rules"><img src="https://img.shields.io/badge/always_on_rules-6-green" alt="Rules"></a>
  <a href="docs/EXTENSIONS.md"><img src="https://img.shields.io/badge/plugins-18-orange" alt="Plugins"></a>
<!-- END GENERATED: badges -->
</p>

<p align="center">
  One command installs the whole thing: standards, skills, subagents, hooks, MCP servers,<br>
  and the macOS tools that let Claude see your screen, drive your apps, and read anything you point it at.
</p>

<p align="center">
  <b>A sidekick you have to instruct is not a sidekick.</b> Standards load themselves, skills fire on<br>
  what you asked for, hooks run on their own, and the install finishes itself.
</p>

---

## Table of Contents

- [What It Does](#what-it-does)
- [The Idea](#the-idea)
- [What Gets Installed](#what-gets-installed)
- [Quick Start](#quick-start)
- [Full Infrastructure Setup](#full-infrastructure-setup)
- [Classes and Life](#classes-and-life)
- [Second Brain](#the-second-brain)
- [Design System](#the-design-system)
- [Standards Files](#the-standards-files)
- [Verifying the Install](#verifying-the-install)
- [Hooks](#the-hooks)
- [Slash Commands](#the-slash-commands)
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

## What it does

You talk to it normally. It figures out which part of itself to use.

| You say                                       | What happens                                                           |
| --------------------------------------------- | ---------------------------------------------------------------------- |
| "what did this video actually say"            | Pulls the transcript and summarizes it. Works on articles and PDFs too |
| "what's on my calendar Thursday"              | Reads Calendar. Same for Contacts, Mail, Notes, and Reminders          |
| "text Mom I'm running late"                   | Drafts it, sends it through Messages, reads the thread back to confirm |
| "look at my screen and tell me what's broken" | Takes a screenshot, inspects the window, can click and type in it      |
| "what's due this week"                        | Reads the ledger built from your syllabi, with attendance math         |
| "remember that I hate em dashes"              | Writes it to your notes so every future session already knows          |
| "clean up this draft"                         | Returns the rewritten text, keeps your voice, strips the AI tells      |
| "why is this page slow"                       | The full engineering setup: standards, review, debugging, deploy       |

Nothing in that table is a command you have to look up. You describe what you
want and the right skill loads itself.

Hold `fn` and talk instead of typing, if you prefer. Dictation runs on your Mac,
and nothing is uploaded.

---

## The idea

A good sidekick already knows the ship. You should not have to tell yours where
the standards are, which skill applies, or that it is allowed to look at your
screen. A slash command you have to remember is a slash command you will not
use, so every layer here is chosen for whether it fires on its own:

| Layer          | Fires when                                         | You type |
| -------------- | -------------------------------------------------- | -------- |
| Standards      | Every session, or when the work touches that stack | Nothing  |
| Skills         | Your request matches what the skill is for         | Nothing  |
| Subagents      | The task matches the agent's job                   | Nothing  |
| Hooks          | You save a file, start a session, or end one       | Nothing  |
| macOS tools    | Claude needs to see a window or read a link        | Nothing  |
| Slash commands | You want a specific routine on purpose             | `/name`  |

Slash commands are last on that list for a reason. They are there when you want
them, and nothing depends on you remembering one.

Anything the installer cannot finish by itself, like a permission checkbox, is
handed to an agent rather than to you: see
[agent-setup](skills/agent-setup).

---

## What gets installed

| Piece                   | Details                                                                                                                                            |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **macOS tools**         | 8 installed alongside the kit: Anki, bd, mac, Maccy, mac-use, peekaboo, summarize, yt-transcript                                                   |
| **Skills and plugins**  | 64 skills (8 shipped here, 3 cloned from upstream, 53 from 1 skill pack) plus 18 plugins across 3 marketplaces                                     |
| **Second brain**        | A private notes repo Claude reads at the start of every session and writes to as things change. Syncs to GitHub                                    |
| **Coursework ledger**   | Your syllabi become deadlines, attendance budgets, and a per-course AI policy Claude checks before touching graded work                            |
| **On-device dictation** | Installs [Plynn](https://github.com/31Carlton7/plynn): hold fn, talk, and clean text appears. Speech and cleanup run on your Mac, nothing uploaded |
| **Smart hooks**         | Format on save, sync your notes, warn on `.env` writes, and flag unpushed work only when there is any                                              |
| **4 subagents**         | context-keeper, code-reviewer, debugger, and explorer, each scoped to one job with its own tool set                                                |
| **Output styles**       | Drop the software-engineering instructions entirely when the work is notes or prose                                                                |
| **18 standards files**  | 6 loaded every session; 12 stack-specific ones that load only when the work touches them                                                           |
| **Full design system**  | Dark mode, shadcn/ui, Tailwind, scroll-aware navbar, real typography, for when you are building something                                          |
| **48 slash commands**   | For when you want a specific routine on purpose. You never need one to get the rows above                                                          |

---

## Quick Start

Clone it, then let Claude do the install:

```bash
git clone https://github.com/calebnewtonusc/Chewbacca
cd Chewbacca
claude "run the setup skill"
```

Nothing installed yet? That is the expected case. macOS ships bash and curl and
not much else, so `bin/bootstrap.sh` installs the Command Line Tools, Homebrew,
gh, node, jq, uv and the claude CLI first. Claude runs it for you and waits at
the three points that need you: the Command Line Tools dialog, the Homebrew
password prompt, and signing in to GitHub.

Claude asks what it needs in chat, runs the installer with your answers, reads
the results back, and hands you the two or three things that need a real click
in System Settings. There is no terminal questionnaire.

The installer takes every answer as a flag, so you can drive it yourself:

```bash
./setup.sh --name Jane --repo-dir ~/dev
./setup.sh --help          # every flag
./setup.sh --dry-run --name Jane   # what it would change, changing nothing
./setup.sh --only tools    # re-run one section after a tool arrives late
```

Two things stay off unless you ask for them by name. `--bypass-permissions`
stops Claude asking before it runs commands or writes files, everywhere, and
takes three files to undo. `--session-opener prayer` opens every reply with a
prayer. Credentials are written only when passed on that run, never read from
your shell or keychain, and the installer prints each one it writes.

<details>
<summary>Already a developer with your own setup?</summary>

Drop the standards and commands into one existing project without touching your
global config:

```bash
curl -fsSL https://raw.githubusercontent.com/calebnewtonusc/Chewbacca/main/install.sh | bash
```

Or take the 50-line quick-start standards file alone:

```bash
curl -fsSL https://raw.githubusercontent.com/calebnewtonusc/Chewbacca/main/CLAUDE-QUICK.md > CLAUDE.md
```

</details>

---

## Full infrastructure setup

The `setup.sh` script collects your name, GitHub username, and API keys, then:

1. Creates `{your-name}-context` (private GitHub repo) with personal brain templates
2. Creates `claude-context` (public GitHub repo) with operational instructions
3. Writes `~/.claude/settings.json`, pointing at the hook scripts
4. Installs commands, rules, subagents, and hooks into `~/.claude/`
5. Installs the skills, marketplaces, and plugins listed in [settings/toolkit.json](settings/toolkit.json)
6. Configures Composio MCP if you have a URL
7. Runs `doctor.sh` and refuses to claim success if anything failed

You end up with a fully wired Claude setup. Every session starts with your full context loaded. Every edit to your context files auto-commits and auto-pushes.

---

## Classes and life

The kit was a coding toolkit for its first six months, which meant it had
nothing to say about the other half of the week. A syllabus is the most
structured document a student is ever handed: every date they will be judged on,
the exact cost of an absence, and a written statement of what help is allowed.
Almost nobody reads it twice, and Claude was re-reading the PDF every time it was
asked a question the PDF already answered.

So the syllabus becomes a ledger, once, and everything else reads from it.

### The ledger

```
~/coursework/
  semester.yml        term dates, drop deadlines, breaks
  courses/*.yml       one file per course
  syllabi/            the source PDFs, so any claim can be re-checked
```

Build it with `/syllabus path/to/syllabus.pdf`. Set `COURSEWORK_DIR` to put it
somewhere else. It is plain YAML, so it belongs in a private repo next to your
personal context, and it is yours: nothing in this public repo knows what
classes you are taking.

### The CLI

```bash
coursework due --days 14      # what is due, soonest first
coursework today              # today's classes and today's deadlines
coursework week               # the days ahead, one block each
coursework attendance         # absences used against the budget
coursework grade BISC --target 90
coursework policy WRIT ai     # what this course allows
coursework ics --out ~/Desktop/semester.ics
coursework check              # validate the ledger, loudly
```

Deterministic, dependency-free, and `--json` on every read command. Claude runs
it instead of parsing YAML by hand, which means deadline questions cost a shell
call rather than a page of reasoning. The SessionStart hook runs `due` and puts
the next few deadlines in context before the first question.

**It never writes to the ledger.** Deadlines are facts copied from a document,
and a program that rewrites them can quietly disagree with the source. Claude
and you edit the files; the tool only reads them.

`coursework check` is the part that earns its place. It reports deadlines with no
`source`, courses with no AI policy recorded, grading weights that do not sum to
100, and past-due items still marked `todo`. None of those stop the CLI. All of
them make it lie by omission.

### The AI policy gate

Three courses in one term can have three different rules: banned outright,
allowed with mandatory prompt disclosure, allowed for ideation but not for the
submitted artifact. Getting that wrong is an academic integrity referral, not a
style problem.

So `policies.ai` is a required field, quoted verbatim from the syllabus, and the
`coursework` skill says out loud what a course permits before helping with
anything graded. An unrecorded policy is treated as a ban.

### The three skills

| Skill          | Covers                                                                                      |
| -------------- | ------------------------------------------------------------------------------------------- |
| `coursework`   | The ledger, syllabus intake, grading models including labor contracts, integrity rules      |
| `study-system` | Retrieval practice over rereading, cards, exam run-ups, and the four-cause postmortem       |
| `life-ops`     | The weekly review, life admin with real deadlines, and what to cut when a week does not fit |

Full walkthrough: [docs/SCHOOL.md](docs/SCHOOL.md).

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

**Turning off prompts takes two files, not one.** `permissions.defaultMode` in
`~/.claude/settings.json` covers the CLI. The VS Code extension gates bypass
mode behind its own switch, `claudeCode.allowDangerouslySkipPermissions`, and
ignores the CLI setting until that switch is on, which is why people set
`defaultMode` and keep getting prompted anyway. `setup.sh` now merges both keys
plus `claudeCode.initialPermissionMode` into your editor's user `settings.json`,
from the template in [`settings/vscode-settings.json`](settings/vscode-settings.json).
VS Code, VS Code Insiders, Cursor, VSCodium, and Windsurf are all handled, and
only the editors actually installed are touched. Restart the editor afterward.

Existing settings are merged, not replaced: a comment-laden `settings.json` is
parsed as JSONC, the original is copied to `settings.json.d1-backup` first, and
a file too broken to parse is left alone with instructions printed instead. Your
own values win on every key except the two that do the bypassing, so re-running
`setup.sh` will not undo a deliberate choice you made about the cosmetic ones.

**The Claude desktop app needs a third file.** It runs its own bundled copy of
the CLI and reads `~/.claude/settings.json`, so `defaultMode` covers its chat
and code sessions with nothing extra. Coding tasks dispatched from the app are
the exception: they read `dispatchCodeTasksPermissionMode` from the app's own
config store, which ships as `acceptEdits`, so edits go through and bash
commands still stop and ask. `setup.sh` sets it to `bypassPermissions`. Quit
Claude first. The app holds that config in memory and writes the whole file back
when it saves, so a change made while it is running gets dropped.

**`bypassPermissions` only counts from `~/.claude/settings.json`.** Put it in a
project's `.claude/settings.json` or `.claude/settings.local.json` and the
resolver discards it, because otherwise cloning a repo would be enough to turn
off someone else's permission prompts. There is no error in the UI, just
prompts you thought you had turned off. `doctor.sh` checks for it, along with
the managed-settings policy that can disable bypass mode outright.

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

## The slash commands

You do not need these. Ask for what you want in plain words and the right thing
loads itself. They exist for the times you want one specific routine, run the
same way every time, without describing it again.

Skim once, forget them, and come back if you ever want one.

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

Classes and life:

| Command       | What it does                                                       |
| ------------- | ------------------------------------------------------------------ |
| `/syllabus`   | Read a syllabus end to end into the ledger, every date sourced     |
| `/due`        | What is due, soonest first, and the one thing to start now         |
| `/week`       | The week ahead: classes, deadlines, and whether the load fits      |
| `/class-prep` | Next session: what is due, what to read, what to bring             |
| `/study`      | A study plan built backwards from the exam date and material range |
| `/quiz`       | Active recall drill, one question at a time, graded honestly       |
| `/lecture`    | Notes or slides into retrieval questions, cards, and confusions    |
| `/reading`    | Work an assigned reading against the prompt that will grade it     |
| `/postmortem` | After a graded exam, sort every wrong answer by cause              |
| `/grades`     | Where the grade stands and what the remaining work has to do       |
| `/attendance` | Absence budget, what the next one costs, how to buy it back        |
| `/life`       | Weekly review: what shipped, what is stuck, what got dropped       |

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

| Doc                                                        | What It Covers                                                                                                            |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| [docs/METHODOLOGY.md](docs/METHODOLOGY.md)                 | The five principles of vibe coding, the D1 workflow loop, anti-patterns, measuring effectiveness                          |
| [docs/CLOUDFLARE.md](docs/CLOUDFLARE.md)                   | D1 query patterns, migrations, Drizzle ORM, Worker routing (vanilla + Hono), D1 + KV + R2, deployment                     |
| [docs/PROMPTS.md](docs/PROMPTS.md)                         | 20+ real prompts for scaffolding, features, debugging, database work, UI design, deployment                               |
| [docs/SCHOOL.md](docs/SCHOOL.md)                           | Running a semester: the coursework ledger, the CLI, the three skills, and the per-course AI policy gate                   |
| [docs/SYSTEM-PROMPTS.md](docs/SYSTEM-PROMPTS.md)           | Eight techniques for agent-governing prompts: priority order, confidence thresholds, format contracts, and what to delete |
| [docs/INTERNALS.md](docs/INTERNALS.md)                     | How Claude Code works under the hood: CLAUDE.md loading, hooks, tools, agents, context compression                        |
| [docs/SKILLS.md](docs/SKILLS.md)                           | What this kit ships, the four public skill registries, the licensing traps in them, and how to write your own             |
| [docs/EXTENSIONS.md](docs/EXTENSIONS.md)                   | Skills, plugins, and MCP: what each layer is for, what setup.sh installs, and which to reach for first                    |
| [docs/STARRED-AUDIT.md](docs/STARRED-AUDIT.md)             | Every repo the author starred, checked against what setup.sh installs, with a reason for each                             |
| [docs/MACOS-TOOLS.md](docs/MACOS-TOOLS.md)                 | The five macOS tools setup.sh installs: permissions, auth, usage, and the agent-scripts skill pack                        |
| [docs/SWIFT-MACOS-PORTING.md](docs/SWIFT-MACOS-PORTING.md) | Running a Swift app below its declared macOS floor: availability gating, weak linking, verifying with otool               |
| [docs/MACOS-APP-CONTROL.md](docs/MACOS-APP-CONTROL.md)     | Driving Calendar, Contacts, Mail, Messages, and Notes from an agent: the TCC model, the JSON contract, where it is weak   |

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

**Score them before you trust them.** `skill-scan` reads every skill on disk and
grades it on five dimensions with no model in the loop: whether the description
is precise enough to route, whether the skill executes code or asks the model to
guess, whether the core file stays lean, whether it does one job, and whether its
scripts do anything surprising.

```bash
skill-scan                  # every skill in ~/.claude/skills, worst first
skill-scan --issues         # what actually lost points
skill-scan path/to/skill    # one skill
skill-scan --min 60         # exit 1 if any skill scores below 60, for CI
```

The dimension to read with judgment is determinism. A skill whose whole job is
prose is correct to have no scripts and will score low there by design. Read it
as a question rather than a defect: could code have done that step instead of
the model? The one thing the score cannot see is how often a skill actually
fires, which is the thing that matters most.

`setup.sh` installs all of it. What you get:

<!-- BEGIN GENERATED: extensions -->

| Extension                                                                                                 | Layer  | What it does                                                                                   |
| --------------------------------------------------------------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------- |
| [skills/agent-setup](skills/agent-setup)                                                                  | Skill  | Finishing the install steps that need a browser or a permission dialog                         |
| [skills/coursework](skills/coursework)                                                                    | Skill  | Your syllabi as a ledger: deadlines, attendance math, per-course AI policy                     |
| [skills/graph-engineering](skills/graph-engineering)                                                      | Skill  | Knowledge graphs and agent task graphs, with teaching mode                                     |
| [skills/life-ops](skills/life-ops)                                                                        | Skill  | The weekly review, life admin with real deadlines, and what to cut                             |
| [skills/second-brain](skills/second-brain)                                                                | Skill  | Reading, writing, and auditing your personal context repo                                      |
| [skills/setup](skills/setup)                                                                              | Skill  | Installing the kit by conversation instead of a terminal questionnaire                         |
| [skills/stack-rules](skills/stack-rules)                                                                  | Skill  | The 12 stack-specific standards, loaded only when the work needs them                          |
| [skills/study-system](skills/study-system)                                                                | Skill  | Retrieval practice over rereading, exam run-ups, and the four-cause postmortem                 |
| [avoid-ai-writing](https://github.com/conorbronsdon/avoid-ai-writing)                                     | Skill  | Audit and rewrite content to remove AI writing patterns ("AI-isms").                           |
| [no-ai-slop](https://github.com/petergyang/no-ai-slop)                                                    | Skill  | Edit drafts into sharper, more human writing while preserving the writer's personal voice, or… |
| [youtube-transcripts](https://github.com/calebnewtonusc/claude-youtube-transcripts)                       | Skill  | Get the transcript of a YouTube video, channel, or playlist.                                   |
| [agent-scripts](https://github.com/steipete/agent-scripts) (53)                                           | Pack   | Peter Steinberger's shared agent skills: macOS, Swift, GitHub, release ops                     |
| [claude-md-management](https://github.com/anthropics/claude-plugins-official)                             | Plugin | Audits the standards file this kit installs, so it does not rot                                |
| [context7](https://github.com/anthropics/claude-plugins-official)                                         | Plugin | Real library docs on demand instead of the model's training recall                             |
| [feature-dev](https://github.com/anthropics/claude-plugins-official)                                      | Plugin | A seven-phase build: requirements, architecture, tests, review, docs                           |
| [frontend-design](https://github.com/anthropics/claude-plugins-official)                                  | Plugin | Design judgment, so a generated UI is not three cards on a gradient                            |
| [hookify](https://github.com/anthropics/claude-plugins-official)                                          | Plugin | Reads a session and writes the hook that stops the thing that annoyed you                      |
| [humanizer](https://github.com/blader/humanizer)                                                          | Plugin | Strips the Wikipedia-catalogued signs of AI writing out of a draft                             |
| [security-guidance](https://github.com/anthropics/claude-plugins-official)                                | Plugin | Warns on the edit, not in review, when a change looks unsafe                                   |
| [session-report](https://github.com/anthropics/claude-plugins-official)                                   | Plugin | An explorable report of what a session actually cost and did                                   |
| [understand-anything](https://github.com/Egonex-AI/Understand-Anything)                                   | Plugin | Turns a codebase into an interactive knowledge graph you can query                             |
| bigquery-data-analytics, expo, pinecone, playwright, pyright-lsp, railway, serena, typescript-lsp, vercel | Plugin | Language servers, browser automation, deploys, and data tooling                                |
| [prompt-optimizer](https://github.com/linshenkx/prompt-optimizer)                                         | MCP    | Rewrites and iterates on prompts through three MCP tools, self-hosted                          |

<!-- END GENERATED: extensions -->

That table is generated. `~/.claude/hooks/sync-to-d1.sh` reads what is actually
installed on the author's machine and rewrites it, along with the install list in
`setup.sh` and the manifest at [settings/toolkit.json](settings/toolkit.json). A
skill reaches this list only if it carries a public upstream URL or ships in this
repo, so a personal skill added locally stays local. MCP servers are opt-in by
name for the same reason.

Full breakdown of which layer to reach for, and why, in [docs/EXTENSIONS.md](docs/EXTENSIONS.md).

---

## macOS tools

Claude can read and write files all day and still be blind to the rest of the
machine. These five close that gap: screen and UI control, Google Workspace,
long-form reading, and a clipboard that remembers. All are third-party and
installed alongside the kit, not vendored into it.

<!-- BEGIN GENERATED: cli -->

| Tool                                                                          | Install                                                                | What it does                                                                 |
| ----------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| [Anki](https://github.com/ankitects/anki)                                     | `brew install --cask anki`                                             | Spaced repetition, where the flashcards the study skills write actually live |
| [bd](https://github.com/gastownhall/beads)                                    | `brew install beads`                                                   | Issue tracker your agent reads and writes, so work survives a context reset  |
| [mac](https://github.com/31Carlton7/mac-cli)                                  | see docs/MACOS-APP-CONTROL.md (clone plus swift build, no formula yet) | Calendar, Reminders, Contacts, Mail, Messages, Notes, and Finder as JSON     |
| [Maccy](https://github.com/p0deje/Maccy)                                      | `brew install --cask maccy`                                            | Clipboard history, so a value scrolled past is still recoverable             |
| [mac-use](https://github.com/browser-use/macOS-use)                           | see docs/MACOS-TOOLS.md (clone plus a uv venv, no formula)             | Natural-language agent that drives any Mac app through Accessibility         |
| [peekaboo](https://github.com/openclaw/Peekaboo)                              | `brew install steipete/tap/peekaboo`                                   | Screenshots, UI inspection, and click/type automation for any macOS app      |
| [summarize](https://github.com/steipete/summarize)                            | `brew install steipete/tap/summarize`                                  | Gist of any URL, YouTube video, podcast, or local file                       |
| [yt-transcript](https://github.com/calebnewtonusc/claude-youtube-transcripts) | see docs/MACOS-TOOLS.md (its own installer, no formula)                | Transcript of any YouTube video, channel, or playlist, read without asking   |

<!-- END GENERATED: cli -->

`summarize` and `mac-use` both run on the Claude CLI you already have, so
neither needs an API key. `peekaboo` needs Screen Recording and Accessibility
granted once, which is what the [agent-setup](skills/agent-setup) skill exists
for: after `setup.sh`, run

```bash
claude "run the agent-setup skill and finish whatever doctor.sh says is missing"
```

and Claude does the CLI work itself, stopping only at the checkbox that is
genuinely yours to click. Setup, permissions,
and the failure modes are in [docs/MACOS-TOOLS.md](docs/MACOS-TOOLS.md).

That table is generated the same way the extension table is: a tool appears only
once the generator finds it on the machine, so an entry here is proof of an
install rather than an intention.

### Plynn: on-device dictation

Setup also installs [Plynn](https://github.com/31Carlton7/plynn) by Carlton
Aikins (MIT). Hold the fn key, talk, release, and cleaned-up text lands wherever
your cursor is. Speech recognition, AI cleanup, your dictionary, and your history
all run on your Mac. There is no account and no transcript upload.

Talking is faster than typing, and a prompt you dictate tends to carry more
context than one you type. That is the whole reason it is in a Claude Code kit.

It needs Apple Silicon. Which path setup takes depends on your macOS version:

| Your macOS          | What happens                                                       |
| ------------------- | ------------------------------------------------------------------ |
| 26 (Tahoe) or newer | Downloads Carlton's notarized release. Fast, nothing to build.     |
| 15 (Sequoia)        | Skipped by default. Upstream targets 26, so it has to be compiled. |

On macOS 15 it does run, it just has to be built with a compatibility patch
(about 20 minutes, needs Xcode 26):

```bash
PLYNN_BUILD_FROM_SOURCE=1 ./bin/install-plynn.sh
```

What that patch does and what the fallbacks cost is in
[patches/README.md](patches/README.md). The general technique, for any Swift app
whose declared macOS floor is higher than it needs to be, is in
[docs/SWIFT-MACOS-PORTING.md](docs/SWIFT-MACOS-PORTING.md).

Plynn is installed from Carlton's repository and releases, never vendored into
this one. `PLYNN_FORCE=1` reinstalls over an existing copy.

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
Chewbacca/
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
│   ├── commands/                # 48 slash commands, dev plus coursework and life
│   ├── rules/                   # 6 always-on standards, imported by CLAUDE.md
│   ├── hooks/                   # Hook scripts (format, sync, session, stop, env guard)
│   └── agents/                  # 4 subagents (context-keeper, reviewer, debugger, explorer)
├── docs/
│   ├── METHODOLOGY.md           # Vibe coding philosophy and workflow
│   ├── CLOUDFLARE.md            # D1/Workers/KV/R2 patterns and examples
│   ├── PROMPTS.md               # Example AI prompts for every stage of dev
│   ├── SYSTEM-PROMPTS.md        # How to write the prompt that governs an agent
│   ├── SCHOOL.md                # Running a semester: ledger, CLI, skills, AI policy gate
│   ├── INTERNALS.md             # How Claude Code works under the hood
│   ├── EXTENSIONS.md            # Skills, plugins, MCP: which layer to reach for
│   ├── MACOS-TOOLS.md           # Screen control, Workspace, summarization, clipboard
│   ├── SWIFT-MACOS-PORTING.md   # Running a Swift app below its declared macOS floor
│   └── MACOS-APP-CONTROL.md     # Native macOS apps as JSON, for agents
├── bin/
│   ├── ai-scan                  # Scores prose for AI-writing tells, no model
│   ├── skill-scan               # Scores skills on whether they will fire, no model
│   ├── coursework               # Reads the semester ledger: due, attendance, grades, ics
│   ├── mac-use                  # CLI for macOS-use, which ships none upstream
│   ├── mac_use_claude.py        # Runs mac-use on the Claude CLI, no API key
│   ├── peekaboo                 # Forces local execution, skips the broken Bridge
│   ├── chrome-js                # Read and click a Chrome tab through JavaScript
│   └── mac_use_cli.py           # The agent loop behind mac-use
├── examples/
│   └── todo-app/                # Working Worker + D1 example (deploy in 60s)
├── patches/                     # plynn-macos15.patch, applied to upstream at install
├── templates/                   # Full starter files (Worker, migration, components)
│   └── coursework/              # semester.yml and course.yml, the ledger shape
├── snippets/                    # Copy-paste patterns (Drizzle, wrangler, hooks)
├── skills/
│   ├── second-brain/            # Operating the personal context repo
│   ├── graph-engineering/       # Knowledge graphs and agent task graphs
│   ├── stack-rules/             # 12 stack standards, loaded on demand
│   ├── coursework/              # Syllabus intake, grading models, integrity
│   ├── study-system/            # Retrieval practice, exam prep, reading
│   └── life-ops/                # Weekly review, capacity, what to cut
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
