# What this reads, where it goes

Local storage and local processing are different. This inventory describes the
stores and external processing paths so you can choose what to share.

Runtime-only setup creates empty context and configures the chosen agent. It
does not import personal sources or enable a session opener. Existing choices
remain in place. Full Mac setup installs additional tools and integrations;
preview its profile before running it.

## What the kit reads

| Source            | Where it lives                                | Read by                                                 |
| ----------------- | --------------------------------------------- | ------------------------------------------------------- |
| iMessage history  | `~/Library/Messages/chat.db`                  | the `texts` and `people` skills, needs Full Disk Access |
| Contacts          | the macOS Contacts store                      | the `people` skill                                      |
| Calendar          | the macOS Calendar store, or a connector      | `mac-brief`, `life-ops`                                 |
| Email             | an MCP connector, not a local index           | `mac-followups`, `mac-brief`                            |
| Screen            | screenshot and accessibility tree, on request | the `mac-*` skills                                      |
| Your files        | whatever you point it at                      | everything                                              |
| Your context repo | `~/second-brain` or wherever you put it       | `second-brain`, every session start                     |

## What the kit stores, and where

| Store                     | Path                                            | Encrypted               | Survives uninstall                              |
| ------------------------- | ----------------------------------------------- | ----------------------- | ----------------------------------------------- |
| People and interactions   | `~/.chewbacca/people/`                          | no                      | yes, and you are offered an export first        |
| Hook and doctor logs      | `~/.chewbacca/logs/`, `~/.chewbacca/doctor.log` | no                      | yes                                             |
| Session context cache     | `~/.chewbacca/cache/`                           | no                      | yes                                             |
| Install manifest          | `~/.chewbacca/install-manifest.json`            | no                      | archived, not deleted                           |
| Coursework ledger         | `~/coursework/`                                 | no                      | yes                                             |
| Context repo              | yours                                           | no                      | yes, untouched                                  |
| Runtime rollback receipts | `~/.chewbacca/runtime-installs/`                | no; owner-only files    | retained while needed for rollback              |
| Codex turn receipts       | `$CODEX_HOME/chewbacca-turn-state/`             | no; owner-only database | retained; latest request and execution receipts |

Chewbacca does not encrypt these stores itself. Owner-only file permissions limit
other accounts; they do not stop software running as your account. Disk encryption
and provider retention settings are separate controls.

## What leaves your Mac

The destination depends on the active agent, model provider and connected tools:

- **To the active model provider:** conversation content, including personal
  context loaded by hooks and relevant files or messages read by tools. Claude,
  Codex and other hosts use their configured accounts and providers.
- **To a configured MCP server or connector:** its tool inputs and any content
  needed for the requested operation. Installed connections depend on the chosen
  setup path and existing configuration.
- **For `people distill`:** selected message content goes through its Claude model
  backend. Importing messages locally and sending them for model processing are
  separate actions.
- **To an API you gave a key to:** Todoist, GitHub, and anything else you wired
  up.

Software installation also downloads from package registries and source hosts.
Do not include sensitive material in public bug reports, logs or repository pushes.

## What you can turn off

- `CHEWBACCA_NO_CACHE=1` stops the session context cache.
- Leave data imports unused; installing a skill is not consent to scan a source.
- Review tool permissions and revoke unwanted connections in the selected host.
  OS data grants belong to the app actually executing the read.
- `chewbacca agent remove --runtime NAME` reverses recorded adapter changes when
  the files still match. It preserves the shared brain and later user edits.
- Review export contents before moving or sharing a backup. Uninstalling the kit
  does not erase local personal stores or copies already sent to providers.

## What is missing, honestly

Chewbacca does not yet provide universal redaction, a verified local-only mode
across all tools, per-person indexing exclusions, automatic retention limits or
an audit of everything a connected server accessed. Related work is tracked in
[1000.md](1000.md), items 546 through 570.
