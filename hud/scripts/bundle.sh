#!/usr/bin/env bash
# Wrap the binary in a real .app so it can be double-clicked, kept in the Dock,
# and set to launch at login. SwiftPM produces a bare executable; macOS wants a
# bundle with an Info.plist before it will treat something as an app.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/BobHUD.app"
CONFIG="release"
# --universal builds both architectures and fuses them, so one download runs
# on an Intel Mac and an Apple Silicon one. Off by default: a developer
# rebuilding every few minutes should not pay for the half they cannot run.
UNIVERSAL=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    debug|release) CONFIG="$arg" ;;
    *) echo "usage: bundle.sh [debug|release] [--universal]" >&2; exit 2 ;;
  esac
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$UNIVERSAL" -eq 1 ]; then
  # Two passes and lipo, not `swift build --arch arm64 --arch x86_64`.
  # The multi-arch flag routes SwiftPM through xcbuild, which ships with
  # Xcode and not with the Command Line Tools, so it fails on a machine that
  # has only the tools with "xcbuild executable ... does not exist". Keeping
  # a full Xcode off the build requirements is the same call the presence
  # field's shader makes by compiling from source at launch, and two passes
  # plus a fuse need neither.
  #
  # The passes are also kept apart from the plain native build above, which
  # they used to follow. Sharing one .build between an unqualified build and
  # an --arch one leaves SwiftPM reporting "swift-version--<hash>.txt not
  # registered" and producing nothing.
  echo "Building $CONFIG for arm64 and x86_64…"
  for arch in arm64 x86_64; do
    swift build -c "$CONFIG" --arch "$arch" >/dev/null
  done
  lipo -create -output "$APP/Contents/MacOS/BobHUD" \
    "$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/BobHUD" \
    "$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)/BobHUD"
  echo "  $(lipo -info "$APP/Contents/MacOS/BobHUD" | sed 's/.*are: //')"
else
  echo "Building ($CONFIG)…"
  swift build -c "$CONFIG" >/dev/null
  # Ask SwiftPM where it put the binary rather than spelling the triple out.
  # The path was hardcoded to `.build/arm64-apple-macosx/`, correct on every
  # Mac this was ever built on and wrong on an Intel one, where SwiftPM
  # writes `x86_64-apple-macosx` and the build died at the copy having
  # already compiled cleanly. A machine nobody tests on is a machine this
  # has to work on, because it is the machine somebody else owns.
  BIN="$(swift build -c "$CONFIG" --show-bin-path)"
  [ -x "$BIN/BobHUD" ] || { echo "no binary at $BIN/BobHUD" >&2; exit 1; }
  cp "$BIN/BobHUD" "$APP/Contents/MacOS/BobHUD"
fi

# The commit count, so two builds of different code never share a version
# and a bundle can be matched back to the commit it came from.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>Bob HUD</string>
  <!-- The identifier and executable stay: the microphone grant is keyed to
       the identifier. What the person sees is the assistant's name. -->
  <key>CFBundleDisplayName</key>     <string>Chewbacca</string>
  <key>CFBundleIdentifier</key>      <string>dev.bobthebuilder.hud</string>
  <key>CFBundleExecutable</key>      <string>BobHUD</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>0.1.0</string>
  <key>CFBundleVersion</key>         <string>$BUILD</string>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <!-- Accessory: no Dock icon, no app switcher entry, never steals focus. -->
  <key>LSUIElement</key>             <true/>
  <key>NSHighResolutionCapable</key> <true/>
  <!-- Both are required before the frameworks will even prompt. Without them
       the app is killed on the first call rather than being denied. -->
  <key>NSMicrophoneUsageDescription</key>
  <string>Bob HUD listens only while you hold the globe key, or on a wake word if you turn that on. Recognition runs on this Mac.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Speech is turned into text on this Mac so you can ask for something without typing. Nothing is sent anywhere.</string>
</dict>
</plist>
PLIST

# Ad-hoc signing is enough to run locally and keeps macOS from re-prompting
# about an unsigned binary on every launch.
#
# The designated requirement is spelled out because the default one for an
# ad-hoc signature is the binary's own hash, and that is what macOS keys the
# microphone and speech grants to. On 2026-09-19 every rebuild came up with a
# new hash, tccd logged "Failed to match existing code requirement" for
# dev.bobthebuilder.hud, and the app prompted for both permissions again; with
# nobody at the Mac to click, `authorized` stayed false and a press of the
# globe key opened nothing. Pinning the requirement to the bundle identifier
# is what a signing certificate would do, without needing one in the keychain.
codesign --force --sign - --identifier dev.bobthebuilder.hud \
  --requirements '=designated => identifier "dev.bobthebuilder.hud"' "$APP" 2>/dev/null \
  || echo "  (unsigned; it will still run)"

echo "Built $APP"
echo
echo "  open $APP                    launch it"
echo "  cp -r $APP /Applications/    keep it"
echo
echo "To launch at login: System Settings > General > Login Items, add Bob HUD."
