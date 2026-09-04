#!/usr/bin/env bash
# Installs Plynn, a fully on-device Mac dictation app, forked from Carlton
# Aikins' work (https://github.com/31Carlton7/plynn, MIT) and vendored at
# plynn/ in this repo. See plynn/NOTICE.md for what we changed and why it is
# carried here rather than patched at install time.
#
# It is always built from the vendored source. The upstream DMG is not used
# even on macOS 26, because it does not contain Chewie.
#
# Safe to re-run. Never overwrites an existing /Applications/Plynn.app.
set -uo pipefail

GRN='\033[0;32m'; YLW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "  ${GRN}✓${NC} $1"; }
warn() { echo -e "  ${YLW}!${NC} $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$SCRIPT_DIR/plynn"
APP="/Applications/Plynn.app"

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

# ── Build the vendored source ─────────────────────────────────────────────────
if [ "$MACOS_MAJOR" -lt 15 ]; then
  warn "Plynn needs macOS 15 or newer, skipping"
  exit 0
fi

# Compiling is a 20 minute step, so it stays opt-in rather than something
# setup.sh springs on someone who only wanted the CLIs.
if [ "${PLYNN_BUILD_FROM_SOURCE:-0}" != "1" ]; then
  warn "Plynn skipped: it has to be compiled (Xcode 26, roughly 20 minutes)"
  echo "    To install it:  PLYNN_BUILD_FROM_SOURCE=1 $SCRIPT_DIR/bin/install-plynn.sh"
  exit 0
fi

command -v xcodebuild &>/dev/null || { err "Xcode 26 required to build Plynn"; exit 0; }
[ -d "$SRC/Sources" ] || { err "missing vendored source at $SRC"; exit 0; }

if ! xcodebuild -showComponent MetalToolchain 2>/dev/null | grep -q "Status: installed"; then
  warn "downloading the Metal toolchain (MLX's shaders need it, this is large)"
  xcodebuild -downloadComponent MetalToolchain 2>/dev/null \
    || { err "could not install the Metal toolchain"; exit 0; }
fi

cd "$SRC" || exit 0
log "building the vendored source at $SRC"

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
