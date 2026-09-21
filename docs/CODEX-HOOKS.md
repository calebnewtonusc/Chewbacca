# Chewbacca hooks in Codex

`python3 tools/codex_hooks.py install` merges five native lifecycle hooks into
`$CODEX_HOME/hooks.json` (default `~/.codex/hooks.json`). Existing app hooks stay
in place. The first install preserves a `hooks.json.before-chewbacca` backup.
The regular setup also installs these definitions.

For an existing checkout, `bash setup.sh --only agents` installs the shared
context instructions and native hooks without installing Mac tools or changing
model selection. It discovers the registered second brain or existing Claude
context. Set `CHEWBACCA_BRAIN_DIR` to choose a different folder. Reruns preserve
existing notes, global instructions, symlinks and other apps' hooks.

Codex requires review and trust of new or changed hook definitions. Inspect them
in the CLI's `/hooks` browser. Until trusted, the startup instruction reader remains
the fallback. Do not edit trust databases or bypass hook trust to activate them.

| Event            | Behavior                                                                         |
| ---------------- | -------------------------------------------------------------------------------- |
| SessionStart     | Fresh shared briefing and second-brain health check, including after compaction  |
| UserPromptSubmit | Existing literal opener preference, coursework context and kit routing           |
| PreToolUse       | Environment-file warning for every affected patch path                           |
| PostToolUse      | Installed Prettier, application draft checks and prose checks for affected files |
| Stop             | Reply lint with one corrective continuation; working-tree reminder               |

Codex passes patches through `tool_input.command`, while the shared Claude file
checks consume `tool_input.file_path`. The adapter expands additions, updates,
deletions and renames, then runs post-edit checks only on files that still exist.
The reply guard's legacy output is translated to Codex's `decision: block` and
`reason` fields; `stop_hook_active` prevents endless correction loops.

File hooks cover native `apply_patch`, `Write`, and `Edit` events. They do not
claim to intercept arbitrary shell scripts or remote editing tools. Prefer
`apply_patch` for local edits; explicitly run the relevant checks after shell writes.
Missing optional application checks are skipped. Formatting requires an installed
Prettier; the hook does not download executables during an edit.
The shared shell checks require `jq`; setup reports when it is missing. The
bundled prose scanners work without installing separate launcher commands.

Private briefing text is read live, not copied into configuration or a log.
`chewbacca-hook-status.json` records only the most recent event, timestamp and
successful adapter completion. A direct test can also write this marker, so it
alone does not prove the Codex host triggered the event.

The adapter does not copy Claude permissions or MCP configuration, automatically
stage or publish work, run the inventory sync, or bypass macOS data permissions.
Those are distinct operations from lifecycle checks.

Reference: [Codex hooks](https://learn.chatgpt.com/docs/hooks).

Validation: `python3 tests/test_codex_hooks.py` exercises actual event shapes,
multi-file patches, rename paths, per-turn reply guards, fresh context after
compaction, and configuration preservation.
