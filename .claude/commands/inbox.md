---
description: Instantly scan iMessage inbox, surface pending replies, priorities, and unreads
allowed-tools: Bash(bun:*), Bash(cd:*), Read
---

# Inbox

Run the iMessage agent scan immediately. No setup, no confirmation.

> **Requires**: iMessage agent installed via `setup.sh`. macOS only.

Find the iMessage agent directory (check `$HOME/dev/imessage-agent` or search for it):

```bash
IMSG_DIR="${IMESSAGE_AGENT_DIR:-$HOME/dev/imessage-agent}"
if [ -d "$IMSG_DIR" ]; then
  cd "$IMSG_DIR" && bun run agent.ts --mode scan 2>&1
else
  echo "iMessage agent not found. Run setup.sh to install, or set IMESSAGE_AGENT_DIR."
fi
```

After the scan, synthesize:

- Who needs a reply (sorted by urgency)
- Any time-sensitive messages
- Conversation threads that have gone cold

If $ARGUMENTS is "full" or "triage":

```bash
cd "$IMSG_DIR" && bun run agent.ts --mode inbox 2>&1
```

If $ARGUMENTS is "run":

```bash
cd "$IMSG_DIR" && bun run agent.ts --mode run --dry-run 2>&1
```

Always surface the results immediately. Never ask the user to run this themselves.
