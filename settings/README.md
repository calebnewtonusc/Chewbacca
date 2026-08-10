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
