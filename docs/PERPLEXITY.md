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

## Voice to Perplexity

The voice can hand a sentence to Perplexity Computer the same way it hands one
to a Claude Code tab. `bin/perplexity-tab` drives a signed-in Perplexity tab in
Chrome through the page's own controls, and `hud-listen` routes to it.

Say it by name, and only by name:

- "Ask Perplexity to research Clay's pricing tiers"
- "Perplexity, find three Clay waterfall templates for SaaS founders"
- "No, Perplexity" within fifteen seconds sends the last sentence there instead
- "And also..." right after a Perplexity turn stays in the same session

Perplexity is never a guess. Neither the rules nor Jev can pick it, because it
is a second agent with its own credits. The voice says "to Perplexity", stays
free while the turn runs, and reads the first line of the answer when it lands.
The whole answer goes to the conversation panel. If Computer stops to ask you
something, the voice says "Perplexity is waiting on you in Chrome".
"What are my agents doing" includes the Perplexity tab.

```
perplexity-tab status --json        idle | busy | absent, and why
perplexity-tab ask --new "..."      fresh session, send, wait, print the answer
perplexity-tab send "..."           continue the session in the tab
perplexity-tab wait --after N       the answer after N finished turns
```

Needs View > Developer > Allow JavaScript from Apple Events in Chrome's Default
profile, which `chrome-js --check` reports. Setup links `perplexity-tab` into
`~/.local/bin` with the other browser bridges. Tested live on 2026-09-24: a
fresh session answered a one-word prompt and the bridge read it back.

Commands that Perplexity itself runs on the Mac have no network and cannot
send Apple events to Chrome, so this bridge is for the voice and your own
Terminal, not for Perplexity driving itself.
