#!/bin/bash
# Chewbacca bootstrap: get a bare Mac to the point where setup.sh can run.
#
# The prerequisite check used to print five errors and quit, and one of them
# was "Install: brew install gh" on a machine that has no brew. That is a
# dead end for exactly the person this kit claims to be for: someone whose Mac
# has Claude on it and nothing else.
#
# What macOS actually ships: bash, curl, and stubs at /usr/bin/git and
# /usr/bin/python3 that do nothing until the Command Line Tools are installed.
# Recent macOS also ships jq. Everything else is on us.
#
#   ./bin/bootstrap.sh            install what is missing
#   ./bin/bootstrap.sh --check    report only, change nothing
#
# Two steps need a human and cannot be automated away:
#   1. The Command Line Tools installer is a GUI dialog with a button.
#   2. Homebrew asks for your password, because it writes outside your account.
# Both are reported as BLOCKED with the exact thing to do.
set -uo pipefail

GRN='\033[0;32m'; RED='\033[0;31m'; YLW='\033[1;33m'; BLD='\033[1m'; NC='\033[0m'
ok()      { echo -e "  ${GRN}✓${NC} $1"; }
miss()    { echo -e "  ${YLW}!${NC} $1"; }
blocked() { echo -e "  ${RED}BLOCKED${NC} $1"; }
step()    { echo -e "\n${BLD}$1${NC}"; }

CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1
NEEDS_HUMAN=0
UV_MISSING=0

# Homebrew lands in different places on Apple Silicon and Intel, and it is not
# on PATH in the shell that just installed it.
brew_bin() {
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && { echo "$b"; return 0; }
  done
  command -v brew 2>/dev/null
}

step "Command Line Tools (git and python3 are stubs without them)"
if xcode-select -p &>/dev/null; then
  ok "installed"
else
  miss "not installed"
  if [ "$CHECK_ONLY" -eq 0 ]; then
    xcode-select --install &>/dev/null || true
    blocked "a dialog just opened. Click Install, wait for it to finish, then re-run this."
  else
    blocked "run: xcode-select --install"
  fi
  NEEDS_HUMAN=1
fi

step "Homebrew"
BREW="$(brew_bin)"
if [ -n "$BREW" ]; then
  ok "installed ($BREW)"
else
  miss "not installed"
  if [ "$CHECK_ONLY" -eq 0 ] && [ "$NEEDS_HUMAN" -eq 0 ]; then
    echo "  Installing. It will ask for your password: it writes outside your account."
    # NONINTERACTIVE skips the "press RETURN" pause. It does not skip sudo.
    if NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
      BREW="$(brew_bin)"
      [ -n "$BREW" ] && ok "installed" || blocked "installed but not found on PATH"
    else
      blocked "Homebrew install failed. See https://brew.sh"
      NEEDS_HUMAN=1
    fi
  else
    blocked 'run: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    NEEDS_HUMAN=1
  fi
fi

# Put brew on PATH for the rest of this script and for future shells. A fresh
# install prints this instruction and most people miss it, then nothing works.
if [ -n "$BREW" ]; then
  eval "$("$BREW" shellenv)" 2>/dev/null || true
  BREW_PREFIX="$("$BREW" --prefix 2>/dev/null)"
  for rc in "$HOME/.zprofile" "$HOME/.bash_profile"; do
    [ -f "$rc" ] || continue
    grep -q "$BREW_PREFIX/bin/brew shellenv" "$rc" 2>/dev/null && continue
    [ "$CHECK_ONLY" -eq 0 ] && {
      printf '\neval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX" >> "$rc"
      ok "added brew to $(basename "$rc")"
    }
  done
fi

step "Tools setup.sh needs"
install_brew_pkg() {
  local cmd="$1" pkg="${2:-$1}"
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd"
    return 0
  fi
  miss "$cmd missing"
  if [ "$CHECK_ONLY" -eq 1 ] || [ -z "$BREW" ]; then
    blocked "run: brew install $pkg"
    return 1
  fi
  if "$BREW" install "$pkg" &>/dev/null; then
    ok "$cmd installed"
  else
    blocked "brew install $pkg failed"
    return 1
  fi
}

install_brew_pkg gh || NEEDS_HUMAN=1
install_brew_pkg node || NEEDS_HUMAN=1
# Recent macOS ships jq at /usr/bin/jq. Only install it when it is genuinely absent.
install_brew_pkg jq || NEEDS_HUMAN=1

step "uv (macOS-use runs in its own Python environment)"
if command -v uv &>/dev/null; then
  ok "uv"
elif [ "$CHECK_ONLY" -eq 1 ]; then
  blocked "run: curl -LsSf https://astral.sh/uv/install.sh | sh"
  UV_MISSING=1
else
  if curl -LsSf https://astral.sh/uv/install.sh 2>/dev/null | sh &>/dev/null; then
    export PATH="$HOME/.local/bin:$PATH"
    command -v uv &>/dev/null && ok "uv installed" || miss "uv installed but not on PATH yet"
  else
    miss "uv install failed. macOS-use will be skipped; everything else still works."
    UV_MISSING=1
  fi
fi

step "The claude CLI"
if command -v claude &>/dev/null; then
  ok "claude"
elif command -v npm &>/dev/null && [ "$CHECK_ONLY" -eq 0 ]; then
  if npm install -g @anthropic-ai/claude-code &>/dev/null; then
    ok "claude installed"
  else
    blocked "run: npm install -g @anthropic-ai/claude-code"
    NEEDS_HUMAN=1
  fi
else
  # Not optional. Without it setup.sh installs no plugins at all.
  blocked "run: npm install -g @anthropic-ai/claude-code"
  NEEDS_HUMAN=1
fi

step "GitHub sign-in"
if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  ok "signed in as $(gh api user --jq .login 2>/dev/null)"
else
  blocked "run: gh auth login    (opens a browser, needs your GitHub account)"
  NEEDS_HUMAN=1
fi

step "Git identity"
if [ -n "$(git config --global user.name 2>/dev/null)" ] &&
  [ -n "$(git config --global user.email 2>/dev/null)" ]; then
  ok "$(git config --global user.name) <$(git config --global user.email)>"
else
  blocked 'run: git config --global user.name "Your Name"'
  blocked '     git config --global user.email "you@example.com"'
  NEEDS_HUMAN=1
fi

echo ""
if [ "$NEEDS_HUMAN" -eq 0 ] && command -v gh &>/dev/null && gh auth status &>/dev/null; then
  echo -e "  ${GRN}Ready.${NC} Next: claude \"run the setup skill\""
  [ "$UV_MISSING" -eq 1 ] &&
    echo -e "  ${YLW}!${NC} uv is still missing, so mac-use will be skipped. Everything else runs."
  exit 0
fi
echo -e "  ${YLW}Some steps need you.${NC} Do the BLOCKED lines above, then re-run this."
exit 1
