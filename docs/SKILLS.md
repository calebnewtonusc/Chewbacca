# Skills: what this kit ships, and where to find more

A skill is a directory with a `SKILL.md` whose frontmatter description tells
Claude when to load it. It costs nothing until the description matches the task,
which is why a 40KB reference can sit there indefinitely and only appear when
relevant.

Install to `~/.claude/skills/<name>/` for every project, or
`.claude/skills/<name>/` for one. `/skills` lists what is loaded.

## What this kit ships

| Skill                                                                 | Loads when                                                                                 |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| [second-brain](../skills/second-brain)                                | Reading or writing the personal context repo, or auditing it for rot                       |
| [stack-rules](../skills/stack-rules)                                  | Writing UI, API, database, deploy, test, or accessibility code                             |
| [graph-engineering](../skills/graph-engineering)                      | Building knowledge graphs, or orchestrating agents as task graphs                          |
| [no-ai-slop](https://github.com/petergyang/no-ai-slop)                | Editing a draft, or checking whether prose reads as machine-written                        |
| [avoid-ai-writing](https://github.com/conorbronsdon/avoid-ai-writing) | A thorough writing audit, editing a file in place, or scanning docs with its Node detector |
| [humanizer](https://github.com/blader/humanizer)                      | A second opinion on a draft, working from Wikipedia's signs-of-AI-writing catalogue        |

`second-brain` is the one that does not exist anywhere else. Every registry
below has skills for talking to APIs; none of them have a skill for keeping a
personal knowledge base honest, which is the actual job when you use Claude as
a second brain.

## Where to find more

Four directories, all worth knowing, none worth copying wholesale.

**[awesome-skills.com](https://awesome-skills.com/)** is the most practical.
157+ skills with install commands attached, spanning tooling, security, design,
data, and MCP. Start here.

**[awesomeclaude.ai/awesome-claude-skills](https://awesomeclaude.ai/awesome-claude-skills)**
lists 204 skills across 13 categories with search and filtering. Strong on
scientific and research tooling, including a 125-skill bioinformatics set.

**[ComposioHQ/awesome-claude-skills](https://github.com/ComposioHQ/awesome-claude-skills)**
is a repo, not a link list, with 864 real `SKILL.md` files. 832 of those are
Composio app integrations that need a Composio account; the other 32 are
standalone and several are Anthropic's own. Read the licensing section below
before copying any of them.

**[VoltAgent/awesome-openclaw-skills](https://github.com/VoltAgent/awesome-openclaw-skills)**
indexes roughly 5,400 skills across 30 categories. Note carefully: these are
**OpenClaw** skills, not Claude Code skills. OpenClaw is a persistent daemon
with messaging channels, so a large share of that catalogue assumes an
always-running agent that can text you, watch your calendar, or control your
house. Those assumptions do not hold here and the skills will not work
unmodified. Treat it as a source of ideas, not a source of files.

## Licensing, which is not boilerplate here

Two real traps, both found by reading the frontmatter rather than the repo
badge:

- The four `document-skills` in the Composio repo (docx, pdf, pptx, xlsx)
  declare `license: Proprietary`. They cannot be redistributed. Install them
  from their source if you want them; do not vendor them into your own repo.
- `twitter-algorithm-optimizer` is **AGPL-3.0**. Copying it into an MIT or
  Apache repo relicenses your work by contagion.

The repo badge said Apache 2.0. Two of its skills are not. Check the `license:`
line in each `SKILL.md` before you copy anything.

## Adding a skill

Clone from upstream rather than copying files into this repo. The skill stays
updatable, keeps its own license next to it, and you avoid inheriting terms you
did not read.

```bash
./add-skill.sh https://github.com/petergyang/no-ai-slop
./add-skill.sh https://github.com/some/repo --path skills/thing
```

`add-skill.sh` clones shallow into a temp dir, finds the `SKILL.md`, copies the
skill directory plus any `LICENSE` next to it into `~/.claude/skills/`, and
prints the declared license so you see it before it lands.

## Writing your own

The shape is a directory, a `SKILL.md`, and optional `references/` and
`scripts/`. The description is the whole game: it is the only thing Claude sees
when deciding whether to load the skill, so write it as a list of the situations
that should trigger it, not as a summary of the contents.

Weak: "Helps with databases."
Working: "Use when writing Supabase schema, RLS policies, migrations, or
queries, or when a query returns the wrong rows."

Keep `SKILL.md` short and push the bulk into `references/`, so the trigger stays
cheap and the detail loads only once the skill is already engaged.
