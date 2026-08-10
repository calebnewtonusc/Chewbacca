# iMessage Agent Integration

Give Claude the ability to read your iMessage inbox and send messages. Built on the native macOS `chat.db` SQLite database + AppleScript. No BlueBubbles or third-party servers required.

## What it does

- Reads your recent conversations from `~/Library/Messages/chat.db`
- Surfaces unread messages, pending replies, and priority contacts
- Sends messages via AppleScript (same as if you typed them in Messages.app)
- Runs the `/inbox` slash command to instantly see your message backlog

## Prerequisites

- macOS (required — uses native Messages.app)
- Terminal must have Full Disk Access (System Preferences → Privacy → Full Disk Access)
- Messages.app signed in with Apple ID

## Setup

### 1. Grant read permission in Claude settings

Add to `~/.claude/settings.json` under `permissions.allow`:

```json
"Read(/Users/YOUR_USERNAME/Library/Messages/**)"
```

### 2. Grant Bash permission for osascript

Add to `~/.claude/settings.json` under `permissions.allow`:

```json
"Bash(osascript:*)",
"Bash(sqlite3:*)"
```

### 3. Test it works

In a Claude Code session:

```
/inbox
```

Claude will scan `chat.db`, surface your unread messages, and show you what needs replies.

## How Claude reads messages

```bash
sqlite3 ~/Library/Messages/chat.db "
SELECT
  datetime(message.date/1000000000 + 978307200, 'unixepoch', 'localtime') as time,
  handle.id as sender,
  message.text
FROM message
JOIN handle ON message.handle_id = handle.ROWID
WHERE message.is_from_me = 0
  AND message.date > (strftime('%s', 'now') - 86400) * 1000000000
ORDER BY message.date DESC
LIMIT 50;"
```

## How Claude sends messages

```applescript
tell application "Messages"
  set targetService to 1st service whose service type = iMessage
  set targetBuddy to buddy "PHONE_OR_EMAIL" of targetService
  send "MESSAGE_TEXT" to targetBuddy
end tell
```

## MCP bridge (advanced)

For a full MCP server that wraps this into structured tools Claude can call natively, see `_System/composio-imessage-bridge/` in your D1 repo. It exposes:

- `read_messages(contact, limit)`: fetch recent messages
- `send_message(to, body)`: send a message
- `search_messages(query)`: full-text search

### Wire it into .mcp.json:

```json
{
  "mcpServers": {
    "imessage": {
      "command": "tsx",
      "args": ["/path/to/your/imessage-bridge/index.ts"],
      "env": {}
    }
  }
}
```

## Privacy note

`chat.db` contains all your messages. The bridge only runs locally — nothing is sent to any external server. Claude reads the DB file directly on your machine.
