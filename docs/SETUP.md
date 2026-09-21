# Setup Guide

## Shared context for Claude and Codex

All setup profiles configure the shared personal-context reader and five native
Codex hooks. Codex is optional; install and sign in to it separately. No model
choice, account credentials, or private context is copied into the repository.

For an existing Chewbacca installation, run `bash setup.sh --only agents` from
the checkout. This discovers your existing context folder and preserves its
contents. Use `CHEWBACCA_BRAIN_DIR=/path/to/brain` to select another folder.
Fresh setups create additive templates, including voice and a memory index.

Review and trust the five Chewbacca definitions in Codex's `/hooks` browser.
Until trusted, the global startup instructions still load your context through
the reader. New tasks and compacted sessions load it automatically once trusted.
The feature does not install Codex, change macOS permissions or publish notes.
See [event mappings and requirements](CODEX-HOOKS.md).

## Prerequisites

- [Claude Code](https://claude.ai/code) installed
- [gh CLI](https://cli.github.com/) installed and authenticated (`gh auth login`)
- Node.js 18+

---

## Option A: One-command install

```bash
git clone https://github.com/calebnewtonusc/Chewbacca
cd Chewbacca
chmod +x install.sh && ./install.sh
```

---

## Option B: Manual setup (5 minutes)

### 1. Copy CLAUDE.md

**Per-project** (recommended to start):

```bash
cp CLAUDE.md /path/to/your/project/CLAUDE.md
```

**Global** (affects all projects):

```bash
cp CLAUDE.md ~/.claude/CLAUDE.md
```

### 2. Copy .claude/ directory

```bash
cp -r .claude/ /path/to/your/project/.claude/
```

### 3. Merge settings

Open `settings/settings.json` and merge its contents into `~/.claude/settings.json`.

If you don't have `~/.claude/settings.json` yet, just copy it:

```bash
cp settings/settings.json ~/.claude/settings.json
```

If you already have one, manually merge the `hooks` and `env` blocks.

---

## Configuration

### Required environment variables

Add these to `~/.claude/settings.json` under `"env"`:

```json
{
  "env": {
    "GITHUB_TOKEN": "your_github_personal_access_token",
    "TODOIST_API_TOKEN": "your_todoist_api_token"
  }
}
```

**GITHUB_TOKEN**: Generate at github.com/settings/tokens, needs `repo` + `workflow` scopes.

**TODOIST_API_TOKEN**: Get at app.todoist.com/app/settings/integrations/developer, optional, only needed for `/daily-brief`, `/sprint`, `/todo`, `/done`.

### Your GitHub username

The `/new-project` and `/close-loop` commands use `gh api user --jq .login` to auto-detect your GitHub username. Make sure `gh auth login` is done.

---

## Verify it's working

Open Claude Code in any project and run:

```
/new-project test-app A test project
```

You should see it scaffold a full Next.js app with shadcn/ui, Tailwind, all deps, and push a private repo to your GitHub.

---

## Customizing

### Change the default accent color

In `CLAUDE.md`, find `indigo` and replace with your preferred color (`violet`, `blue`, `emerald`, `rose`).

### Swap the database

The database standards in `skills/stack-rules/references/database.md` assume Supabase. Replace the contents with your ORM or database of choice.

### Add your own commands

Drop a `.md` file in `.claude/commands/` with this frontmatter:

```markdown
---
description: What this command does
allowed-tools: Bash(git:*), Read, Edit, Write
argument-hint: "<required-arg> [optional-arg]"
---

# Command Name

Steps...
```

Invoke it with `/command-name` in Claude Code.

## Optional Codex and browser backends

Claude Code stays the primary agent after setup. Codex is optional: an existing
installation is detected, and absence does not fail setup or doctor. From this
repository, `codex` discovers generated `AGENTS.md`. Setup refreshes that export
from `instructions/agent-neutral.md` and installs the same source for Claude.
It also installs the native [Codex hook adapter](CODEX-HOOKS.md). Review and trust
its five definitions in Codex before they run; unrelated hooks are preserved.

Setup links `mac-use`, `chatgpt-tab`, and `chatgpt-gateway` into `~/.local/bin`
on repeated runs. macOS-use owns only the upstream runtime and venv, selected by
`MACOS_USE_HOME` or `~/Projects/macOS-use`. Existing runtime installations do not
prevent launcher updates. See [macOS app control](MACOS-APP-CONTROL.md) for Chrome
permissions, provider selection, and the browser security boundary.

For just the secondary-agent instructions and browser launchers, use
`bash setup.sh --only backends`. This focused section installs the four local
launchers (`chatgpt-tab`, `chatgpt-gateway`, `mac-use`, `chrome-js`) and shared
instructions without installing dependencies or changing the upstream runtime.
`--only tools` also refreshes these launchers when the runtime already exists.

### Shared Claude and Codex personal context

Every setup profile configures both agents, even if Codex is installed later.
Claude remains primary. Install and sign in to each agent separately; setup does
not copy credentials, permissions, or Claude settings into Codex. The native
adapter translates the supported shared checks into Codex lifecycle events.

Fresh setup creates `~/dev/<name>-context` (or the selected `--repo-dir`) with
`YOU.md`, `NOW.md`, `PEOPLE.md`, `VOICE.md`, and `memory/MEMORY.md`. Both agents
receive startup instructions to read those same live files. Fill in the templates
with either agent; unfilled placeholders are not treated as personal facts.
Rerunning setup preserves existing notes and adds only missing templates.

The startup blocks preserve existing global instructions, including symlinks.
Codex respects `CODEX_HOME` and an active `AGENTS.override.md`; Claude uses
`~/.claude/CLAUDE.md`. Both flat context folders and existing second brains with
`core/identity.md`, `core/now.md`, `core/people.md`, and `core/voice.md` are supported.
Private facts stay in the shared folder, outside the public AGENTS export.

For an existing installation, run `bash setup.sh --only backends`. It discovers
the registered context folder or existing Claude imports/hook configuration,
falling back to `~/second-brain`. To select a folder explicitly, use
`CHEWBACCA_BRAIN_DIR="/path/to/private context" bash setup.sh --only backends`.
The portable profile configures both agents and local context without Mac tools.
The read-only `python3 tools/codex_context.py status` reports source availability
without printing personal facts. Start new agent sessions after setup, or run the
reader manually in an existing session.
