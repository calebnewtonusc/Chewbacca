#!/bin/bash
# PostToolUse: format the file that was just written, then sync context repos.
#
# Why this is a script and not an inline settings.json command:
#
#   1. Hooks do not inherit an nvm-managed PATH. Prettier's shebang is
#      `#!/usr/bin/env node`, so with nvm the hook cannot find node and dies
#      silently at exit 0. You get no formatting and no error. This resolves
#      the node bin directory itself before calling out.
#
#   2. `npx prettier` re-resolves the package on every single file write, which
#      costs seconds per edit. A project-local or global binary is used first
#      and npx is the last resort.
#
#   3. Staging is by filename. `git add .` in a context repo sweeps up
#      .DS_Store and any stray .env, which contradicts rules/git.md.
#
# Config comes from ~/.claude/d1-config.sh, written by setup.sh.

set -uo pipefail

CONFIG="$HOME/.claude/d1-config.sh"
# shellcheck source=/dev/null
[ -f "$CONFIG" ] && . "$CONFIG"

PERSONAL_CONTEXT_DIR="${PERSONAL_CONTEXT_DIR:-}"
PUBLIC_CONTEXT_DIR="${PUBLIC_CONTEXT_DIR:-}"

f="$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)"
[ -n "$f" ] || exit 0
[ -f "$f" ] || exit 0

# ── Make sure node is reachable ───────────────────────────────────────────────
ensure_node() {
  command -v node >/dev/null 2>&1 && return 0

  # nvm: prefer the aliased default, else the highest installed version.
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  if [ -d "$nvm_dir/versions/node" ]; then
    local alias_file="$nvm_dir/alias/default" target=""
    if [ -f "$alias_file" ]; then
      target="$(cat "$alias_file" 2>/dev/null)"
      [ -n "$target" ] && [ -x "$nvm_dir/versions/node/$target/bin/node" ] && {
        PATH="$nvm_dir/versions/node/$target/bin:$PATH"; export PATH; return 0
      }
    fi
    local newest
    newest="$(ls -1 "$nvm_dir/versions/node" 2>/dev/null | sort -V | tail -1)"
    [ -n "$newest" ] && [ -x "$nvm_dir/versions/node/$newest/bin/node" ] && {
      PATH="$nvm_dir/versions/node/$newest/bin:$PATH"; export PATH; return 0
    }
  fi

  local d
  for d in /opt/homebrew/bin /usr/local/bin /usr/bin; do
    if [ -x "$d/node" ]; then PATH="$d:$PATH"; export PATH; return 0; fi
  done
  return 1
}

# ── Find prettier without paying npx resolution on every write ────────────────
find_prettier() {
  local dir
  dir="$(cd "$(dirname "$f")" 2>/dev/null && pwd)" || return 1
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -x "$dir/node_modules/.bin/prettier" ]; then
      printf '%s' "$dir/node_modules/.bin/prettier"; return 0
    fi
    dir="$(dirname "$dir")"
  done
  if command -v prettier >/dev/null 2>&1; then printf '%s' "prettier"; return 0; fi
  return 1
}

should_format() {
  # Prettier rewrites `@~/path` into `@~~/path` in markdown, which silently
  # breaks every CLAUDE.md import and makes the rules files load nothing. That
  # bug shipped once already and only a fresh-clone test caught it, because the
  # corrupted file still looks fine. Never format a file that declares imports.
  case "$(basename "$f")" in
    CLAUDE.md | CLAUDE-QUICK.md) return 1 ;;
  esac
  grep -q '^@[~./]' "$f" 2>/dev/null && return 1

  case "$f" in
    *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.json | *.css | *.scss | *.html | *.md | *.yaml | *.yml)
      return 0
      ;;
  esac
  return 1
}

if should_format; then
  if ensure_node; then
    if PRETTIER="$(find_prettier)"; then
      "$PRETTIER" --write "$f" --log-level silent 2>/dev/null || true
    else
      # No local or global install, so fall back to npx even though it
      # re-resolves the package on every write.
      npx --yes prettier --write "$f" --log-level silent 2>/dev/null || true
    fi
  fi
fi

# ── Sync context repos ────────────────────────────────────────────────────────
sync_repo() {
  local repo="$1" file="$2" rel
  [ -n "$repo" ] || return 0
  [ -d "$repo/.git" ] || return 0
  case "$file" in "$repo"/*) ;; *) return 0 ;; esac

  rel="${file#"$repo"/}"
  cd "$repo" || return 0
  git add -- "$rel" 2>/dev/null || return 0
  git diff --cached --quiet && return 0
  git commit -q -m "chore: update $rel" 2>/dev/null || return 0
  git push -q origin HEAD 2>/dev/null || true
}

sync_repo "$PERSONAL_CONTEXT_DIR" "$f"
sync_repo "$PUBLIC_CONTEXT_DIR" "$f"

exit 0
