# Extensions: skills, plugins, and MCP

The commands and rules in this repo were the whole story in early 2026. They are not anymore.
Claude Code now loads capability from three separate places, and they solve different problems.
Installing all three is what `setup.sh` does.

| Layer    | Lives in                | Loads              | Good for                                              |
| -------- | ----------------------- | ------------------ | ----------------------------------------------------- |
| Rules    | `~/.claude/rules/`      | On matching files  | Standards you want enforced without asking            |
| Commands | `~/.claude/commands/`   | When you type `/x` | Multi-step procedures you run by name                 |
| Skills   | `~/.claude/skills/`     | On matching intent | Deep domain knowledge too long to keep in context     |
| Plugins  | `claude plugin install` | On matching intent | Skills plus MCP servers plus subagents, versioned     |
| MCP      | `.mcp.json`             | Always             | Live connections to services that hold your real data |

A rule is a paragraph Claude reads. A skill is a directory Claude opens only when the task calls
for it, so a 40KB reference costs nothing until the moment it is relevant. A plugin bundles skills,
MCP servers, and subagents behind one install command and one version number.

## Skills

### Shipped in this repo

**`skills/graph-engineering/`** teaches both halves of graph work: knowledge graphs (ontology
design, entity and relation extraction, fusion, GraphRAG) and task graphs (parallel fan-out,
verifier separation, stop rules, human gates). The knowledge-graph half is distilled and translated
from Southeast University's graduate Knowledge Graph course
([npubird/KnowledgeGraphCourse](https://github.com/npubird/KnowledgeGraphCourse)). In teaching mode
it explains each stage with worked examples and generates diagrams.

Install: `cp -R skills/graph-engineering ~/.claude/skills/`

### Installed from upstream

**[petergyang/no-ai-slop](https://github.com/petergyang/no-ai-slop)** (MIT) removes 20+ patterns of
AI slop from a draft: binary contrasts, throat-clearing, faux-insight setups, colon reveals,
fake-profound kickers, importance puffery. It has a detect-only mode that flags patterns without
rewriting, which is the one to use on someone else's prose.

`setup.sh` clones it rather than vendoring a copy, so it stays updatable and keeps its own license.

Worth knowing: the skill is for editing drafts on request. If you want the rules applied to
everything Claude writes by default, put the pattern list in your `CLAUDE.md` as a standing
instruction. The skill and the standing rule do different jobs.

## Plugins

Two marketplaces cover everything below.

```bash
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add Egonex-AI/Understand-Anything
```

**[Understand-Anything](https://github.com/Egonex-AI/Understand-Anything)** turns a codebase into an
interactive knowledge graph you can explore, search, and ask questions about. It ships subagents for
architecture analysis, domain extraction, and tour building, plus `/understand`, `/understand-chat`,
`/understand-diff`, and a web dashboard. Useful on a repo you did not write, or one you wrote six
months ago.

From the official marketplace:

| Plugin                    | What it gives you                                                      |
| ------------------------- | ---------------------------------------------------------------------- |
| `context7`                | Current library docs on demand, instead of the model's training recall |
| `serena`                  | Symbol-level code navigation and editing across a project              |
| `playwright`              | Browser automation for testing UI and scraping                         |
| `vercel`                  | Deploy, env vars, AI SDK, Next.js guidance                             |
| `railway`                 | Services, databases, environments, deploy troubleshooting              |
| `expo`                    | React Native builds, EAS, app store submission                         |
| `pinecone`                | Vector index management and search                                     |
| `bigquery-data-analytics` | Warehouse queries, forecasting, AI functions                           |

`context7` earns its place fastest. It fetches real documentation for whatever library you are
using, which kills the failure mode where a model confidently writes an API that was renamed
eighteen months ago.

## Order of operations

Reach for the lightest thing that works.

1. A rule, if it is a standard you want applied silently
2. A command, if it is a procedure you invoke by name
3. A skill, if it is knowledge too large to keep loaded
4. A plugin, if someone already built and versioned it
5. An MCP server, if it needs live data from a running service

Writing a skill for something `context7` already does is wasted work. Writing a rule when a one-line
`CLAUDE.md` sentence would do is worse, because rules files are another thing to keep current.

## Verifying what is installed

```bash
claude plugin list
ls ~/.claude/skills/
ls ~/.claude/rules/ ~/.claude/commands/
```

Plugins that need OAuth (Vercel, Railway, Supabase, and the like) install fine but stay inert until
you authorize them. Run `/mcp` in an interactive session to finish that; a headless run cannot do
the browser handoff.
