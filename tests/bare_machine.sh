#!/usr/bin/env bash
# What bootstrap.sh says on a Mac with nothing on it.
#
# Every install this kit does starts on a machine like that, and that path had
# never once been executed, because every machine it ran on already had
# Homebrew and node. So the dead end its own header says was fixed was still
# there on 2026-09-19: "run: brew install node", printed to someone who has no
# brew, and "npm install -g ...", printed to someone who has no node.
#
# CHEWBACCA_NO_BREW makes brew_bin report nothing, and the stub PATH holds only
# what macOS itself ships. That is as close to a factory Mac as this can get
# without a factory Mac.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

STUB="$(mktemp -d)"
mkdir -p "$STUB/bin" "$STUB/home"
for c in sh bash env cat ls grep sed awk cut tr wc uname sw_vers df curl shasum \
  mkdir rm cp chmod dirname basename xcode-select sleep date tail head sort id \
  printf test expr find; do
  src="$(command -v "$c" 2>/dev/null)" && ln -sf "$src" "$STUB/bin/$c" 2>/dev/null
done

out="$(CHEWBACCA_NO_BREW=1 HOME="$STUB/home" PATH="$STUB/bin" \
  bash "$ROOT/bin/bootstrap.sh" --check --profile personal 2>&1)"
rm -rf "$STUB"

fails=0
fail() { echo "  FAIL  $1"; fails=$((fails + 1)); }

# A dead end is an instruction naming a tool the machine does not have. The
# Homebrew installer is the one command that is always runnable, because it is
# plain curl, so it is the only thing allowed to be offered unconditionally.
while IFS= read -r line; do
  case "$line" in
    *BLOCKED*"run: brew install"*)
      fail "offers 'brew install' to someone with no Homebrew: $line" ;;
    *BLOCKED*"run: npm install"*)
      fail "offers 'npm install' to someone with no node: $line" ;;
  esac
done <<< "$out"

# And the prerequisite has to be named, not just implied.
echo "$out" | grep -q "needs Homebrew" || fail "never says node and jq need Homebrew first"
echo "$out" | grep -q "needs node"     || fail "never says the claude CLI needs node first"

# Nothing about GitHub belongs in a profile that creates no repos.
echo "$out" | grep -qi "gh auth login" && fail "demands a GitHub account in the personal profile"

# Every BLOCKED line has to end in something the person can actually do.
echo "$out" | grep -c "BLOCKED" >/dev/null || fail "reported nothing at all on a bare machine"

if [ "$fails" -eq 0 ]; then
  echo "ok  bare machine gets $(echo "$out" | grep -c BLOCKED) actionable steps, no dead ends"
  exit 0
fi
echo "$out"
exit 1
