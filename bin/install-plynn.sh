#!/usr/bin/env bash
# Installs Plynn, a fully on-device Mac dictation app by Carlton Aikins.
# Upstream: https://github.com/31Carlton7/plynn (MIT). This script installs it,
# it does not vendor it: the binary comes from Carlton's signed releases, and the
# macOS 15 path builds his source with a compatibility patch.
#
# Two paths, picked by OS:
#   macOS 26+  download the notarized DMG. Fast, nothing to build.
#   macOS 15   build from source with patches/plynn-macos15.patch, because
#              upstream targets 26. Opt in with PLYNN_BUILD_FROM_SOURCE=1.
#
# Safe to re-run. Never overwrites an existing /Applications/Plynn.app.
set -uo pipefail

GRN='\033[0;32m'; YLW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "  ${GRN}✓${NC} $1"; }
warn() { echo -e "  ${YLW}!${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="$SCRIPT_DIR/patches/plynn-macos15.patch"
APP="/Applications/Plynn.app"
DMG_URL="https://github.com/31Carlton7/plynn/releases/latest/download/Plynn.dmg"

# ── Guards ────────────────────────────────────────────────────────────────────
[ "$(uname -s)" = "Darwin" ] || { warn "Plynn is macOS only, skipping"; exit 0; }

if [ "$(uname -m)" != "arm64" ]; then
  warn "Plynn needs Apple Silicon (speech runs on the Neural Engine), skipping"
  exit 0
fi

if [ -d "$APP" ] && [ "${PLYNN_FORCE:-0}" != "1" ]; then
  log "Plynn already installed, left alone (PLYNN_FORCE=1 to reinstall)"
  exit 0
fi

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"

# ── macOS 26+: the notarized DMG ──────────────────────────────────────────────
if [ "$MACOS_MAJOR" -ge 26 ]; then
  TMP="$(mktemp -d)"
  trap 'hdiutil detach "$TMP/mnt" -quiet 2>/dev/null; rm -rf "$TMP"' EXIT
  if ! curl -fsSL "$DMG_URL" -o "$TMP/Plynn.dmg"; then
    err "could not download Plynn.dmg, get it from github.com/31Carlton7/plynn/releases"
    exit 0
  fi
  mkdir -p "$TMP/mnt"
  if ! hdiutil attach "$TMP/Plynn.dmg" -mountpoint "$TMP/mnt" -nobrowse -quiet; then
    err "could not mount Plynn.dmg"
    exit 0
  fi
  if [ -d "$TMP/mnt/Plynn.app" ]; then
    rm -rf "$APP"
    ditto "$TMP/mnt/Plynn.app" "$APP" && log "Plynn installed (notarized release)"
  else
    err "Plynn.app not found inside the DMG"
    exit 0
  fi
  echo "    Launch it, grant microphone and accessibility, then hold fn and talk."
  exit 0
fi

# ── macOS 15: build the port ──────────────────────────────────────────────────
if [ "$MACOS_MAJOR" -lt 15 ]; then
  warn "Plynn needs macOS 15 or newer, skipping"
  exit 0
fi

if [ "${PLYNN_BUILD_FROM_SOURCE:-0}" != "1" ]; then
  warn "Plynn skipped: upstream targets macOS 26, you are on $(sw_vers -productVersion)"
  echo "    It runs here, but it has to be compiled (Xcode 26, roughly 20 minutes)."
  echo "    To install it:  PLYNN_BUILD_FROM_SOURCE=1 $SCRIPT_DIR/bin/install-plynn.sh"
  exit 0
fi

command -v xcodebuild &>/dev/null || { err "Xcode 26 required to build Plynn"; exit 0; }
[ -f "$PATCH" ] || { err "missing $PATCH"; exit 0; }

if ! xcodebuild -showComponent MetalToolchain 2>/dev/null | grep -q "Status: installed"; then
  warn "downloading the Metal toolchain (MLX's shaders need it, this is large)"
  xcodebuild -downloadComponent MetalToolchain 2>/dev/null \
    || { err "could not install the Metal toolchain"; exit 0; }
fi

SRC="${PLYNN_SRC:-$HOME/Projects/plynn}"
if [ -d "$SRC/.git" ]; then
  log "plynn source already at $SRC"
else
  git clone -q https://github.com/31Carlton7/plynn.git "$SRC" \
    || { err "could not clone plynn"; exit 0; }
  log "plynn cloned to $SRC"
fi

cd "$SRC" || exit 0
if git apply --check "$PATCH" 2>/dev/null; then
  git apply "$PATCH" && log "macOS 15 compatibility patch applied"
elif git apply --reverse --check "$PATCH" 2>/dev/null; then
  log "patch already applied"
else
  err "patch does not apply, upstream has moved. Open an issue on Chewbacca."
  exit 0
fi

# A real certificate beats ad-hoc here: macOS keys accessibility and microphone
# grants to the signature, and ad-hoc is identified by its hash, so every
# rebuild would look like a new app and reset the permissions.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')"
if [ -z "$IDENTITY" ]; then
  IDENTITY="-"
  warn "no Apple Development certificate found, signing ad-hoc"
  echo "    Accessibility and microphone permissions will reset on each rebuild."
fi

echo "    Building Plynn. This takes about 20 minutes."
if IDENTITY="$IDENTITY" ./scripts/make-app.sh --install >/tmp/plynn-build.log 2>&1; then
  log "Plynn built and installed"
  echo "    Grant microphone and accessibility, then hold fn and talk."
  echo "    First dictation waits on the speech model (about 1 GB, downloads on launch)."
else
  err "build failed, see /tmp/plynn-build.log"
  tail -5 /tmp/plynn-build.log | sed 's/^/      /'
fi
