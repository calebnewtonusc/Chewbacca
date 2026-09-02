# Settings Configuration

The `settings.json` template wires up the core behaviors that make this kit useful. Here's what each section does and how to adapt it.

---

## Quick start

Copy `settings.json` into one of these locations depending on your scope:

| File                          | Scope                 | Committed?      | Use for                        |
| ----------------------------- | --------------------- | --------------- | ------------------------------ |
| `~/.claude/settings.json`     | Global (all projects) | No              | Personal defaults              |
| `.claude/settings.json`       | Project               | Yes             | Team-wide settings             |
| `.claude/settings.local.json` | Project-local         | No (gitignored) | Personal overrides per project |

`defaultMode` is the exception to that table. See the tier rule below: the two project files cannot set it to `bypassPermissions`.

---

## `permissions.defaultMode`

Controls whether Claude prompts you before taking actions.

```json
"permissions": {
  "defaultMode": "bypassPermissions"
}
```

| Value                 | Behavior                                  |
| --------------------- | ----------------------------------------- |
| `"default"`           | Prompts for most tool uses                |
| `"acceptEdits"`       | Auto-accepts file edits, prompts for bash |
| `"bypassPermissions"` | Never prompts (full autonomy)             |
| `"plan"`              | Plan-only mode, no execution              |

**Recommendation**: Use `"bypassPermissions"` for solo projects where you trust the work. Use `"default"` in team settings.

### `bypassPermissions` only counts from the user tier

`bypassPermissions`, `auto`, and `dontAsk` are ignored when they come from a project file. Put them in `.claude/settings.json` or `.claude/settings.local.json` and the resolver drops them with a log line saying repo-committed settings cannot default to that mode, then falls back to `default`. Nothing in the UI tells you this happened.

The reason is worth understanding rather than working around: cloning a repo would otherwise be enough to turn off someone's permission prompts, so the mode has to be a decision the machine's owner made. `~/.claude/settings.json` is the only place it counts. `setup.sh` writes it there.

An organization can also switch it off entirely with `permissions.disableBypassPermissionsMode` in managed settings (`/Library/Application Support/ClaudeCode/managed-settings.json` on macOS). Only the managed tier is honored for that key, and when it is set, nothing on this page will help. `doctor.sh` reports it.

---

## Three places prompts come from

Turning prompts off is not one setting. Which ones you need depends on how you run Claude:

| How you run it                              | What to set                                                              |
| ------------------------------------------- | ------------------------------------------------------------------------ |
| Terminal CLI                                | `permissions.defaultMode` in `~/.claude/settings.json`                   |
| VS Code, Cursor, VSCodium, Windsurf         | the same, plus the two `claudeCode.*` keys below                         |
| Claude desktop app, chat and code sessions  | the same, nothing extra                                                  |
| Claude desktop app, dispatched coding tasks | the same, plus `dispatchCodeTasksPermissionMode` in the app's own config |

`setup.sh` writes all four. The sections below say what each one is, so you can undo any of them.

---

## The editor half: `vscode-settings.json`

`defaultMode` alone does not stop prompts inside VS Code. The extension has its own gate, and until it is on, the CLI setting is ignored:

```json
"claudeCode.allowDangerouslySkipPermissions": true,
"claudeCode.initialPermissionMode": "bypassPermissions"
```

The first key permits bypass mode at all. The second picks the mode new conversations start in. Setting only the second does nothing, which is the usual reason someone sets `defaultMode` and still gets asked about every command.

`setup.sh` merges `vscode-settings.json` into your editor's user settings for you. To do it by hand, open the Command Palette, run **Preferences: Open User Settings (JSON)**, and add the two keys. Restart the editor either way; the extension reads them at launch.

Where that file lives:

| Editor   | macOS                                                       | Linux                                   |
| -------- | ----------------------------------------------------------- | --------------------------------------- |
| VS Code  | `~/Library/Application Support/Code/User/settings.json`     | `~/.config/Code/User/settings.json`     |
| Cursor   | `~/Library/Application Support/Cursor/User/settings.json`   | `~/.config/Cursor/User/settings.json`   |
| VSCodium | `~/Library/Application Support/VSCodium/User/settings.json` | `~/.config/VSCodium/User/settings.json` |
| Windsurf | `~/Library/Application Support/Windsurf/User/settings.json` | `~/.config/Windsurf/User/settings.json` |

The rest of the template turns off VS Code's own confirmation dialogs: workspace trust, delete and drag confirmations, the terminal close prompt. Those are not Claude prompts, but they break the same flow. `setup.sh` only writes those where you have no value set, so your own preferences survive a re-run.

Both keys are `scope: machine`, so they belong in user settings. Putting them in a committed `.vscode/settings.json` will not work.

---

## The desktop app half: `dispatchCodeTasksPermissionMode`

The Claude desktop app runs its own bundled copy of the CLI and reads `~/.claude/settings.json`, so `defaultMode` already covers its chat and code sessions. It has no equivalent of the VS Code gate.

Coding tasks dispatched from the app are the exception. They read a separate preference that ships set to `acceptEdits`, so file edits go through and bash commands still stop and ask:

```json
"dispatchCodeTasksPermissionMode": "bypassPermissions"
```

It lives in the app's own config store, not in `settings.json`:

| OS      | Path                                               |
| ------- | -------------------------------------------------- |
| macOS   | `~/Library/Application Support/Claude/config.json` |
| Linux   | `~/.config/Claude/config.json`                     |
| Windows | `%APPDATA%\Claude\config.json`                     |

Accepted values are `default`, `acceptEdits`, `plan`, `auto`, and `bypassPermissions`. Anything else fails the app's schema check, and it responds by renaming the whole file to `config.json.corrupt-<timestamp>` and starting over, so do not hand-edit it loosely.

**Quit Claude before `setup.sh` touches this.** The app holds the config in memory and writes the whole file back, so a change made while it is running is dropped the next time it saves. `setup.sh` warns when it sees the app running. You can also just set it in the app's own settings instead.

The app keeps two other lists that cause prompts, `dispatchTrustedCodeWorkspaces` and `localAgentModeTrustedFolders`. Those are folder-trust grants, specific to paths on your machine, so `setup.sh` leaves them alone. Answer the trust prompt once per folder and it stops asking.

---

## `permissions.allow` / `deny`

Fine-grained control over specific tools when not in bypass mode.

```json
"permissions": {
  "allow": [
    "Bash(git:*)",
    "Bash(npm run:*)",
    "Edit",
    "Read"
  ],
  "deny": [
    "Bash(rm -rf:*)"
  ]
}
```

Rule syntax:

- `"Bash(npm:*)"`: any bash command starting with `npm`
- `"Edit"`: all file edits
- `"Read"`: all file reads

---

## `hooks`

Hooks run shell commands automatically at specific lifecycle events. **This is how you enforce behaviors Claude can't do on its own.** Claude's memory can't trigger automated actions, but hooks can.

### PostToolUse: auto-format after edits

```json
"hooks": {
  "PostToolUse": [{
    "matcher": "Write|Edit",
    "hooks": [{
      "type": "command",
      "command": "jq -r '.tool_input.file_path // .tool_response.filePath' | { read -r f; prettier --write \"$f\"; } 2>/dev/null || true"
    }]
  }]
}
```

### PreToolUse: log bash commands

```json
"PreToolUse": [{
  "matcher": "Bash",
  "hooks": [{
    "type": "command",
    "command": "jq -r '.tool_input.command' >> ~/.claude/bash-log.txt"
  }]
}]
```

### UserPromptSubmit: enforce patterns on every message

```json
"UserPromptSubmit": [{
  "hooks": [{
    "type": "command",
    "command": "echo '{\"systemMessage\": \"Reminder: pray before responding\"}'"
  }]
}]
```

---

## `env`

Inject environment variables into every Claude session.

```json
"env": {
  "TODOIST_API_TOKEN": "your_token_here",
  "ANTHROPIC_API_KEY": "sk-ant-..."
}
```

Note: setting secrets here means they're in a plaintext file. Use this for dev tokens, not production credentials.

---

## `model`

Override the default model.

```json
"model": "claude-opus-5"
```

Available: `claude-opus-5` (default), `claude-sonnet-5` (cheaper high-volume), `claude-haiku-4-5` (fast/cheap).

---

## Hook event reference

| Event              | When it fires                   |
| ------------------ | ------------------------------- |
| `PreToolUse`       | Before a tool runs (can block)  |
| `PostToolUse`      | After a tool completes          |
| `UserPromptSubmit` | When you submit a message       |
| `SessionStart`     | When a new session starts       |
| `Stop`             | When Claude finishes responding |
| `PreCompact`       | Before conversation compaction  |
| `PostCompact`      | After compaction                |

---

## Merging with existing settings

Always **read your existing settings before editing.** Never replace the whole file. Merge new entries into existing arrays.

```bash
cat ~/.claude/settings.json
# then edit, merging new hooks/permissions with existing ones
```
