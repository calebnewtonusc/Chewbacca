#!/bin/sh
# Build hud-voice and put it on the path. The git override is for machines
# with `safe.bareRepository = explicit`, which forbids SwiftPM's cache of
# bare repositories; see docs/MACOS-APP-CONTROL.md for the same trick.
set -eu
cd "$(dirname "$0")"
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  swift build -c release
install -d "$HOME/.local/bin"
install .build/release/hud-voice "$HOME/.local/bin/hud-voice"
echo "installed $HOME/.local/bin/hud-voice"
