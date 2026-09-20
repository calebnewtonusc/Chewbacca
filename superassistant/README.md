# superassistant

The voice assistant's memory, in both directions.

The voice behind the hyper bar (`bin/hud-listen`) runs a lean Claude Code
session: its own short prompt, one tool, none of your Claude Code settings,
because those settings carry a 75k-token briefing into every turn. That kept
it fast and cheap, and it also kept it ignorant: it knew nothing about you,
and nothing you asked it reached anywhere else.

This folder and `bin/superassistant` close both halves of that gap.

## In: the voice reads your second brain

Before every request, the bridge rebuilds the voice assistant's prompt from
`bin/hud-agent.md` plus a digest of your second brain, the directory
`setup.sh` wrote as `PERSONAL_CONTEXT_DIR` in `~/.claude/d1-config.sh`:

- the Identity section of `YOU.md`
- all of `NOW.md`, which is the current state and wins over anything older
- one line per person from the tables in `PEOPLE.md`
- the memory index, `memory/MEMORY.md`
- a map of the rest, with the rule to `cat` a file before answering anything
  about your life, work, people or school, and to run `coursework` for any
  deadline

The prompt is written to `~/.bob/agent-prompt.md` and rewritten only when
those files change, so editing `NOW.md` reaches the voice on the next
request, and an unchanged prompt keeps its cache.

```
superassistant context     the digest, as the voice sees it
superassistant prompt      the whole prompt
```

## Out: every question is kept here

Every request, spoken or typed, and the written answer to it is appended to
`questions.jsonl` in this folder, one JSON object per line:

| field     | meaning                                            |
| --------- | -------------------------------------------------- |
| `at`      | local time, ISO 8601                               |
| `said`    | the request, as heard or typed                     |
| `typed`   | true when it came from the conversation panel      |
| `relayed` | true when the display sent it about something done, such as a click on a guide bubble, rather than the person saying it |
| `answer`  | the whole written answer                           |
| `aside`   | true when the answer was written for the hyper bar |
| `outcome` | `done`, `failed` or `cancelled`                    |
| `session` | the Claude Code session it ran in                  |
| `turn`    | the turn count in that session                     |
| `usage`   | the token usage Claude Code reported               |

```
superassistant recent 10          the last ten, oldest first
superassistant search "civil war" questions or answers with the text
superassistant today              today's
superassistant path               where the log is
```

The session-context hook carries the last five questions into every Claude
Code session's briefing, so a session here knows what you asked out loud a
minute ago, and the voice is told the log exists, so "what did I ask you
yesterday" is answered from it.

## Privacy

The log is a record of what you say to your Mac. It is gitignored and stays
on this machine. `SUPERASSISTANT_DIR` moves it somewhere else; nothing in it
is ever sent anywhere by this kit.

Built with Chewbacca
