# Second Brain: Two-Repo Architecture

The D1 second brain splits into two repos with a hard boundary:

```
claude-context/   PUBLIC, operational instructions for Claude
                  CLAUDE.md, rules/, behavioral standards
                  Contains: how Claude should behave
                  Contains NOTHING about you personally

personal-context/ PRIVATE, who you are and what you're working on
                  YOU.md, NOW.md, PEOPLE.md, SYSTEM.md
                  Contains: your identity, projects, contacts, APIs
```

## Why split?

**claude-context can be public.** It's just a set of coding standards and behavioral rules, no different from a public dotfiles repo. Other devs can fork it. Your AI setup becomes shareable without exposing anything personal.

**personal-context stays private.** Your job history, project URLs, contacts, API key formats, personal stories, none of that bleeds into a public repo.

## What each repo contains

### claude-context (public)

| File        | Purpose                                            |
| ----------- | -------------------------------------------------- |
| `CLAUDE.md` | Full design system + behavioral rules              |
| `rules/`    | 18 rules files (API, components, DB, deploy, etc.) |
| `commands/` | Slash commands for Claude Code                     |
| `hooks/`    | PostToolUse formatters and sync hooks              |

Claude loads this once and knows how to write code, design UIs, and behave.

### personal-context (private)

| File        | Purpose                                                          |
| ----------- | ---------------------------------------------------------------- |
| `YOU.md`    | Who you are: background, skills, goals, working style            |
| `NOW.md`    | Current jobs, active projects, priorities, what's broken         |
| `PEOPLE.md` | Collaborators, teammates, contacts                               |
| `SYSTEM.md` | Tools, APIs, infrastructure, credentials format                  |
| `STACK.md`  | Your specific tech preferences (can overlap with claude-context) |

Claude loads this every session and picks up exactly where you left off.

## Setup (5 minutes)

```bash
cd second-brain
chmod +x init-brain.sh
./init-brain.sh
```

The script creates both repos, fills in templates, and wires the SessionStart hook.

## Agent integrations

- [iMessage Agent](agents/imessage.md): Claude reads and sends your iMessages
- [Composio MCP](agents/composio.md): 100+ integrations: GitHub, Gmail, Calendar, Todoist, Vercel
- [Todoist Session Context](agents/todoist.md): Today's top tasks injected into every session

## The auto-update loop

Once set up, you never touch these files manually. Claude updates them as you work:

| What happened           | File updated |
| ----------------------- | ------------ |
| New job or role         | `NOW.md`     |
| Project ships or dies   | `NOW.md`     |
| New collaborator        | `PEOPLE.md`  |
| New API or tool         | `SYSTEM.md`  |
| Stack preference change | `STACK.md`   |

PostToolUse hook auto-commits and pushes on every write. Your brain stays current.

All glory to God! ✝️❤️
