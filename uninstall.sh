#!/bin/bash
# Undo what setup.sh did.
#
# The kit writes to ~/.claude/settings.json, three separate permission files,
# ~/.claude/{skills,hooks,commands,rules,agents,output-styles}, ~/.local/bin,
# and clones repos. Without this, someone who tried it and wanted it gone had
# to reverse all of that by hand from a 1400-line script, which is not a fair
# thing to ask and is a reason not to try it in the first place.
#
#   ./uninstall.sh --dry-run   list everything it would remove or restore
#   ./uninstall.sh             do it
#   ./uninstall.sh --purge     also remove the CLI tools this installed
#
# Never touched, because they are yours and not ours:
#   your context repos and anything in them
#   your git identity, your gh login
#   Homebrew itself, node, the claude CLI
#   any skill, hook, or setting you added yourself
set -uo pipefail

GRN='\033[0;32m'; RED='\033[0;31m'; YLW='\033[1;33m'; BLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GRN}✓${NC} $1"; }
skip() { echo -e "  ${YLW}·${NC} $1"; }
step() { echo -e "\n${BLD}$1${NC}"; }

DRY=0; PURGE=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --purge) PURGE=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $a"; exit 2 ;;
  esac
done
[ "$DRY" -eq 1 ] && echo -e "${BLD}Dry run. Nothing will change.${NC}"

run() { [ "$DRY" -eq 1 ] && return 0; "$@"; }
CLAUDE_DIR="$HOME/.claude"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

step "Restoring settings.json"
# Only the keys this kit sets. Merging back is safer than restoring a backup,
# because a backup would also revert every unrelated change made since.
if [ -f "$CLAUDE_DIR/settings.json" ]; then
  BACKUP="$CLAUDE_DIR/settings.json.pre-uninstall"
  [ "$DRY" -eq 0 ] && cp "$CLAUDE_DIR/settings.json" "$BACKUP"
  [ "$DRY" -eq 0 ] && ok "current settings copied to $(basename "$BACKUP")"
  DRY="$DRY" python3 - "$CLAUDE_DIR/settings.json" <<'PYEOF'
import json, os, sys

path = sys.argv[1]
dry = os.environ.get("DRY") == "1"
try:
    s = json.load(open(path))
except Exception as e:
    print(f"  ! settings.json unreadable ({e}), left alone")
    raise SystemExit(0)

removed = []

# Permission mode goes back to asking. Anything the user added to allow/deny
# stays: those are their decisions, not ours.
perms = s.get("permissions") or {}
if perms.get("defaultMode") == "bypassPermissions":
    perms["defaultMode"] = "default"
    removed.append("permissions.defaultMode -> default (Claude asks again)")

# Only hooks pointing at scripts this kit installed.
OURS = ("slop-guard.sh", "session-context.sh", "format-and-sync.sh",
        "stop-check.sh", "env-guard.sh", "coursework-context.sh",
        "sync-to-d1.sh", "statusline.sh")
hooks = s.get("hooks") or {}
for event in list(hooks):
    kept = []
    for entry in hooks[event] or []:
        cmds = " ".join(h.get("command", "") for h in (entry.get("hooks") or []))
        if any(o in cmds for o in OURS):
            removed.append(f"hooks.{event} -> {next(o for o in OURS if o in cmds)}")
            continue
        kept.append(entry)
    if kept:
        hooks[event] = kept
    else:
        hooks.pop(event, None)
        removed.append(f"hooks.{event} (now empty)")

# The session opener is a printf hook with no script path, so it needs its own
# check: match on what it injects rather than on a filename.
for entry in list(hooks.get("UserPromptSubmit") or []):
    cmds = " ".join(h.get("command", "") for h in (entry.get("hooks") or []))
    if "prayer" in cmds.lower() or "Begin every response" in cmds:
        hooks["UserPromptSubmit"].remove(entry)
        removed.append("hooks.UserPromptSubmit -> session opener")
if not hooks.get("UserPromptSubmit"):
    hooks.pop("UserPromptSubmit", None)

if isinstance(s.get("statusLine"), dict) and "statusline.sh" in json.dumps(s["statusLine"]):
    s.pop("statusLine")
    removed.append("statusLine")

# Credentials are the user's. Report them, never delete them silently.
for k in ("GITHUB_TOKEN", "ANTHROPIC_API_KEY", "TODOIST_API_TOKEN"):
    if (s.get("env") or {}).get(k):
        print(f"  ! env.{k} left in place. It is your credential: remove it yourself if you want it gone.")

for k in ("includeCoAuthoredBy", "autoMemoryDirectory"):
    if k in s:
        print(f"  · {k} left as you set it")

if not removed:
    print("  · nothing of ours found in settings.json")
else:
    for r in removed:
        print(f"  {'would remove' if dry else 'removed'}: {r}")
    if not dry:
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(s, f, indent=2)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
PYEOF
else
  skip "no settings.json"
fi

step "Editor and desktop permission settings"
for f in "$HOME/Library/Application Support/Code/User/settings.json" \
  "$HOME/Library/Application Support/Cursor/User/settings.json"; do
  [ -f "$f.d1-backup" ] || continue
  if [ "$DRY" -eq 1 ]; then
    ok "would restore $(basename "$(dirname "$(dirname "$f")")") from .d1-backup"
  else
    mv "$f.d1-backup" "$f" && ok "restored $(basename "$(dirname "$(dirname "$f")")")"
  fi
done
DESKTOP="$HOME/Library/Application Support/Claude/config.json"
if [ -f "$DESKTOP.d1-backup" ]; then
  [ "$DRY" -eq 1 ] && ok "would restore the desktop app config" ||
    { mv "$DESKTOP.d1-backup" "$DESKTOP" && ok "restored the desktop app config"; }
fi

step "Skills, hooks, commands, rules, agents, output styles"
# Only what this repo ships, matched by name, plus links into a pack we cloned.
for kind in skills commands rules agents output-styles hooks; do
  src="$SCRIPT_DIR/.claude/$kind"
  [ "$kind" = "skills" ] && src="$SCRIPT_DIR/skills"
  [ -d "$src" ] || continue
  for item in "$src"/*; do
    [ -e "$item" ] || continue
    name="$(basename "$item")"
    target="$CLAUDE_DIR/$kind/$name"
    [ -e "$target" ] || continue
    if [ "$DRY" -eq 1 ]; then ok "would remove $kind/$name"; else rm -rf "$target" && ok "removed $kind/$name"; fi
  done
done
# Pack skills are symlinks into a clone. Remove the links, keep the clone.
PACK_N=0
for l in "$CLAUDE_DIR"/skills/*; do
  [ -L "$l" ] || continue
  case "$(readlink "$l")" in
    *agent-scripts*) [ "$DRY" -eq 1 ] || rm -f "$l"; PACK_N=$((PACK_N + 1)) ;;
  esac
done
[ "$PACK_N" -gt 0 ] && ok "$([ "$DRY" -eq 1 ] && echo would remove) $PACK_N agent-scripts links (the clone stays)"

step "Scripts this kit put on your PATH"
for b in slop-check chrome-js mac-use peekaboo ai-scan; do
  f="$HOME/.local/bin/$b"
  [ -e "$f" ] || continue
  if [ "$DRY" -eq 1 ]; then ok "would remove ~/.local/bin/$b"; else rm -f "$f" && ok "removed ~/.local/bin/$b"; fi
done

step "MCP servers this kit registered"
if command -v claude &>/dev/null; then
  for m in peekaboo; do
    claude mcp list 2>/dev/null | grep -q "^$m:" || continue
    if [ "$DRY" -eq 1 ]; then ok "would unregister $m"; else
      claude mcp remove "$m" --scope user &>/dev/null && ok "unregistered $m"
    fi
  done
else
  skip "claude CLI not found"
fi

step "Homebrew tools"
if [ "$PURGE" -eq 0 ]; then
  skip "kept. Re-run with --purge to remove peekaboo, summarize, maccy, anki, beads"
elif command -v brew &>/dev/null; then
  for p in peekaboo summarize gogcli beads; do
    brew list --formula "$p" &>/dev/null || continue
    if [ "$DRY" -eq 1 ]; then ok "would uninstall $p"; else brew uninstall "$p" &>/dev/null && ok "uninstalled $p"; fi
  done
  for c in maccy anki; do
    brew list --cask "$c" &>/dev/null || continue
    if [ "$DRY" -eq 1 ]; then ok "would uninstall $c"; else brew uninstall --cask "$c" &>/dev/null && ok "uninstalled $c"; fi
  done
fi

step "Left alone on purpose"
skip "your context repos and everything in them"
skip "your git identity and gh login"
skip "Homebrew, node, uv, and the claude CLI"
skip "any credential in settings.json env"
skip "skills, hooks, and settings you added yourself"

echo ""
if [ "$DRY" -eq 1 ]; then
  echo -e "  ${BLD}Dry run. Run without --dry-run to apply.${NC}"
else
  echo -e "  ${GRN}Done.${NC} Restart Claude Code for it to take effect."
  echo "  Your previous settings.json is at ~/.claude/settings.json.pre-uninstall"
fi
