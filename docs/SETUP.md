# Setup Guide

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
