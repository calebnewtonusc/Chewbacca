# Perplexity Computer

Perplexity Computer plugs into Chewbacca the way Claude Code and Codex do: it
reads the same skills and the same private brain. It needs no API key and no MCP
server.

```sh
chewbacca agent export --runtime perplexity-computer --destination ./perplexity
```

The export writes two things:

- `CHEWBACCA.md`, the shared agent-neutral guidance, with no personal paths or contents.
- `skills/<name>.zip`, one zip per repo skill with `SKILL.md` at the root.

Upload the zips in Perplexity under Settings, Skills, or ask Perplexity Computer
to import your local skills and it will package and upload them itself. A skill
whose frontmatter fails `tools/frontmatter.py` is skipped and reported, never
truncated. The 1024-character description cap applies here as it does in Claude
Code and Codex, and the checker enforces it.

## What carries over

| Layer            | In Perplexity                                                     |
| ---------------- | ----------------------------------------------------------------- |
| Skills           | Imported zips, loaded on demand like any Perplexity skill         |
| Personal context | Stays on the Mac; read live through the Perplexity Mac connection |
| Preferences      | Imported once into Perplexity memory from CLAUDE.md and memories  |
| Hooks            | Not run. Perplexity applies its own approval checks               |
| Mac control      | Through the Perplexity Mac connection, not Claude's native tools  |

Perplexity asks before sends, publishes and deletions. Chewbacca does not try to
bypass that; it keeps everything else prompt-free.
