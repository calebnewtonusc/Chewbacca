# What this reads, where it goes

A data inventory, because "it all stays local" is a claim and this is the
evidence for it.

## What the kit reads

| Source | Where it lives | Read by |
| --- | --- | --- |
| iMessage history | `~/Library/Messages/chat.db` | the `texts` and `people` skills, needs Full Disk Access |
| Contacts | the macOS Contacts store | the `people` skill |
| Calendar | the macOS Calendar store, or a connector | `mac-brief`, `life-ops` |
| Email | an MCP connector, not a local index | `mac-followups`, `mac-brief` |
| Screen | screenshot and accessibility tree, on request | the `mac-*` skills |
| Your files | whatever you point it at | everything |
| Your context repo | `~/second-brain` or wherever you put it | `second-brain`, every session start |

## What the kit stores, and where

| Store | Path | Encrypted | Survives uninstall |
| --- | --- | --- | --- |
| People and interactions | `~/.chewbacca/people/` | no | yes, and you are offered an export first |
| Hook and doctor logs | `~/.chewbacca/logs/`, `~/.chewbacca/doctor.log` | no | yes |
| Session context cache | `~/.chewbacca/cache/` | no | yes |
| Install manifest | `~/.chewbacca/install-manifest.json` | no | archived, not deleted |
| Coursework ledger | `~/coursework/` | no | yes |
| Context repo | yours | no | yes, untouched |

Nothing is encrypted at rest. Anything running as your user can read all of it.

## What leaves your Mac

Chewbacca has no server, no account, and no telemetry. It does not phone
anywhere. What leaves is what any Claude Code session sends:

- **To Anthropic:** the conversation, which includes whatever a skill or hook
  put into context. If you ask about your texts, the relevant texts are in that
  request. This is Claude Code's normal operation, not something the kit adds.
- **To an MCP server you registered:** whatever that tool call contains. Twelve
  are installed by default; three of them are third-party services.
- **To an API you gave a key to:** Todoist, GitHub, and anything else you wired
  up.

Nothing goes to the author of this kit. There is nowhere for it to go.

## What you can turn off

- `CHEWBACCA_NO_CACHE=1` stops the session context cache.
- Skip the `people` install and no message index is built.
- `chewbacca setup --no-bypass` restores per-tool permission prompts.
- Remove any MCP server with `claude mcp remove <name>`.
- `chewbacca export` then `chewbacca uninstall` takes your data with you.

## What is missing, honestly

No redaction layer before content reaches a model. No local-model path for
sensitive work. No per-person opt-out from indexing. No retention limit. No
audit of what an MCP server actually accessed. All of it is tracked in
[1000.md](1000.md), items 546 through 570.
