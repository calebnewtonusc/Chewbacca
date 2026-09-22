# Runtime setup

Chewbacca keeps the private brain and shared skills independent of the model and
app. `tools/agent_context.py` owns live context discovery; `tools/shared_checks.py`
runs shared checks. Native adapters handle their host's configuration and events.
The original `codex_context.py` entry point remains compatible with existing hooks.

Choose the host already installed on the machine:

```sh
chewbacca agent plan --runtime auto
chewbacca setup --runtime codex
chewbacca setup --runtime claude-code
chewbacca setup --runtime both
chewbacca agent status --runtime both
```

These commands install the agent integration without Homebrew, GitHub repositories,
provider keys or Mac app setup. The historical full `setup` still installs the
larger Mac toolkit. `setup --runtime NAME --dry-run` prints the adapter plan.
Use `agent setup --brain-dir PATH` to select an existing private brain explicitly.
Fresh setup creates blank, owner-only context files. A name is optional; pass
`--name NAME` only when the person supplied it. Existing notes are preserved.
Output is brief by default; add `--json` for scripts. Personal data imports,
session openers and permission bypass remain separate choices.

| Layer            | Shared source                                                         | Runtime responsibility                                                      |
| ---------------- | --------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Personal context | Private brain; path in `~/.chewbacca/context.json`                    | Load live files at startup without exporting personal contents              |
| Skills           | Repo `skills/`, installed through `~/.chewbacca/skills`               | Claude `.claude/skills`; Codex `.agents/skills`; preserve conflicting names |
| Standards        | `instructions/agent-neutral.md` and historical `.claude/rules/` paths | Native instruction discovery and tool-specific interpretation               |
| Checks           | `tools/shared_checks.py` and historical `.claude/hooks/` scripts      | Claude JSON events; Codex multi-file patches and native output schema       |
| Models           | Host's configured model and provider                                  | Native model IDs, reasoning settings, context limits and authentication     |
| Machine access   | Installed tools                                                       | Grants for the actual host app and OS                                       |

## Existing installations

Setup preserves model/provider configuration, permissions, unrelated hooks and
personal skills. It links repository skills directly into the shared library;
Claude does not need to be installed for Codex setup. Bring additional installed
Claude skills across explicitly with:

```sh
chewbacca agent setup --runtime both --import-claude-skills
```

Conflicts are reported by name and left in place. Existing compatible symlinks
remain valid. Vendor skills retain their tool and platform requirements. Updating
the underlying source updates every linked copy. The old context discovery paths
remain fallback inputs; a shared context setting takes precedence. `CHEWBACCA_HOME`,
`CHEWBACCA_BRAIN_DIR`, `CODEX_HOME`, and `CLAUDE_CONFIG_DIR` support custom homes.
Shared prompt preferences can be stored as `prompt_context` in private
`~/.chewbacca/preferences.json`; older literal Claude opener settings are a fallback.

`chewbacca agent remove --runtime NAME` reverses the adapter's recorded changes.
It restores files only while they still match the installed version, removes only
links it created, and reports later edits it preserved. The shared brain and skill
library remain. Private rollback receipts stay under `~/.chewbacca/runtime-installs`
with owner-only file permissions. Missing context sources and dependencies appear
in setup's result; existing private notes are never replaced with templates.

## Native details

Claude's adapter preserves existing native hooks and adds missing shared checks.
Claude-only plugins, slash commands, subagents, permission UI and opt-in sync hooks
keep their native setup. A fresh adapter uses the shared formatter without private
repository sync. See [Claude's hook reference](https://code.claude.com/docs/en/hooks)
and [skill reference](https://code.claude.com/docs/en/skills).

Codex's adapter translates `apply_patch`, proposed edits, denials and reply checks.
Its private turn receipts track completed commands after writes; they do not prove
that a test was sufficient. Codex requires native review and trust for hook
definitions, including changed matchers. Inspect the host's hook review interface
and run a refusal case plus a permitted case before claiming enforcement. A
configuration file or a direct adapter test alone cannot prove interception in a
live host. See [Codex hooks](https://learn.chatgpt.com/docs/hooks) and
[configuration](https://learn.chatgpt.com/docs/config-file/config-reference).

MCP connections are separate from skills. The existing explicit
`tools/codex_integrations.py --server NAME` importer copies selected private
connection settings and preserves existing destinations. Verify server handshake,
tool inventory and host discovery separately. Login and consent remain host-owned.

## Models and apps

Use the model picker in the active app. For a CLI session, pass a model directly:

```sh
chewbacca agent launch --runtime codex --model YOUR_MODEL_ID
chewbacca agent launch --runtime claude-code --model YOUR_MODEL_ID
```

The launcher passes an argument array to the native executable and preserves the
working directory. It does not rewrite the account, provider, reasoning settings
or global default. The runtime validates model availability. App-specific tools
(desktop automation, browser control, connectors) depend on the active host, even
when the same model runs elsewhere.

## Platforms and additional hosts

macOS and Linux/WSL support the shell adapters with Python 3, Bash and jq. macOS
tools still require macOS and grants for their host. Native Windows currently
supports instruction export; install shell hooks within WSL. This is an explicit
limit of this adapter, separate from the products' own Windows support.

```sh
chewbacca agent export --runtime generic --destination ./agent-instructions
chewbacca agent export --runtime chatgpt-web --destination ./browser-instructions
```

Exports contain public guidance and preserve existing text. Configure the target
host to load the export. Hooks and native skill/tool discovery remain unverified.

Add runtime requirements and official sources in `runtimes/profiles.json`, then
implement the native serializer and event translator. New hosts begin as export
adapters. Add a fresh-home test covering configuration preservation, a real guard
refusal, a permitted operation and missing dependencies before enabling native
setup. Keep OS constraints separate from model capabilities and never silently
replace an unavailable explicitly selected provider with another account.
