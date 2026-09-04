#!/usr/bin/env bash
# Break the "do JavaScript fails in Safari" wall. Two off-by-default toggles.
# Safari must be quit for these to take, and reads them on next launch.
set -uo pipefail
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari AllowJavaScriptFromAppleEvents -bool true
defaults write com.apple.Safari.SandboxBroker ManagedByAppleEvents -bool true 2>/dev/null || true
echo "Safari JS-from-AppleEvents enabled. Quit and reopen Safari for it to take effect."
echo "Then: chewie run 'tell application \"Safari\" to do JavaScript \"document.title\" in front document'"
