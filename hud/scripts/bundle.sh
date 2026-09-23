#!/usr/bin/env bash
# Wrap the binary in a real .app so it can be double-clicked, kept in the Dock,
# and set to launch at login. SwiftPM produces a bare executable; macOS wants a
# bundle with an Info.plist before it will treat something as an app.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Kyber.app"
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
  lipo -create -output "$APP/Contents/MacOS/Kyber" \
    "$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Kyber" \
    "$(swift build -c "$CONFIG" --arch x86_64 --show-bin-path)/Kyber"
  echo "  $(lipo -info "$APP/Contents/MacOS/Kyber" | sed 's/.*are: //')"
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
  [ -x "$BIN/Kyber" ] || { echo "no binary at $BIN/Kyber" >&2; exit 1; }
  cp "$BIN/Kyber" "$APP/Contents/MacOS/Kyber"
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
  <key>CFBundleName</key>            <string>Kyber</string>
  <!-- The identifier and executable stay: the microphone grant is keyed to
       the identifier. What the person sees is the assistant's name. -->
  <key>CFBundleDisplayName</key>     <string>Kyber</string>
  <key>CFBundleIdentifier</key>      <string>dev.bobthebuilder.hud</string>
  <key>CFBundleExecutable</key>      <string>Kyber</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>0.1.0</string>
  <key>CFBundleVersion</key>         <string>$BUILD</string>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <!-- Accessory: no Dock icon, no app switcher entry, never steals focus. -->
  <key>LSUIElement</key>             <true/>
  <key>NSHighResolutionCapable</key> <true/>
  <!-- Both are required before the frameworks will even prompt. Without them
       the app is killed on the first call rather than being denied. -->
  <!-- Without this key macOS terminates the app the instant it opens a video
       device, with no crash dialog and nothing in the app's own log, because
       the kill happens before any of its code runs. Hand control shipped on
       2026-09-21 as correct Swift that could not start for exactly this
       reason. -->
  <key>NSCameraUsageDescription</key>
  <string>Kyber watches for two hand gestures, an open palm to dismiss and a
  pointed finger to say "this one". Frames are read on this Mac by Apple's
  Vision framework and never leave it, and the camera is off unless you turn
  hand control on in the menu.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Kyber listens only while you hold the globe key, or on a wake word if you turn that on. Recognition runs on this Mac.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Speech is turned into text on this Mac so you can ask for something without typing. Nothing is sent anywhere.</string>
</dict>
</plist>
PLIST

# Sign with something that outlives the build when there is anything to sign
# with, and fall back to ad-hoc when there is not.
#
# macOS does not record "this app may use Accessibility". It records a code
# requirement, and for an ad-hoc signature with no team identifier the only
# thing it can pin is the binary's own hash. The grant for dev.bobthebuilder.hud
# was recorded on 2026-09-21 at 05:13:59 against cdhash
# 2efeddb7a49900f9f1d0d2a27e1ea2298b806558; this script rebuilt the bundle at
# 13:40:12 as a4246cb7228c1b8662ccd2972f304ce75777334b. The switch in System
# Settings stayed on, `AXIsProcessTrusted()` answered false, and every click of
# the dictation bubble (since replaced by
# Control-dictation) reopened the dialogue asking for a permission that had
# already been given. Nothing the person does in System Settings can fix that,
# because the switch is already where they put it.
#
# A certificate is what breaks the cycle: the requirement then names the
# certificate and the identifier, both of which survive a rebuild. That is why
# the microphone and speech grants, recorded the same day from the same binary,
# still work: those rows hold `identifier "dev.bobthebuilder.hud"`.
#
# `hud/scripts/signing-identity.sh` makes one. Without it the ad-hoc branch
# still runs and still works; the Accessibility grant is what it costs, and
# `bin/lib/axgrant.py` says so in those words.
IDENTITY="${CHEWBACCA_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Chewbacca Local Signing\)".*/\1/p' | head -1)"
fi
# Anyone who has ever opened Xcode already has an "Apple Development" cert,
# and it pins the requirement to the certificate exactly as the purpose-made
# one does, without the administrator password signing-identity.sh needs.
# Looking only for the name above is why this Mac ran ad-hoc for months with a
# perfectly good identity sitting in its keychain, re-granting Accessibility
# after every rebuild. Developer ID is deliberately not used: that one is for
# distribution, and this signature never leaves the machine.
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null |
    sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
fi

if [ -n "$IDENTITY" ]; then
  if codesign --force --sign "$IDENTITY" --identifier dev.bobthebuilder.hud "$APP" 2>/dev/null; then
    echo "  signed as $IDENTITY; permissions survive this rebuild"
  else
    echo "  ($IDENTITY would not sign; falling back to ad-hoc)"
    IDENTITY=""
  fi
fi

if [ -z "$IDENTITY" ]; then
  # The designated requirement is still spelled out, because it is what the
  # user-level grants key off and those do survive. It does not reach the
  # system-level Accessibility row, which is the one dictation needs.
  codesign --force --sign - --identifier dev.bobthebuilder.hud \
    --requirements '=designated => identifier "dev.bobthebuilder.hud"' "$APP" 2>/dev/null \
    || echo "  (unsigned; it will still run)"
fi

echo "Built $APP"
echo
echo "  open $APP                    launch it"
echo "  cp -r $APP /Applications/    keep it"
echo
echo "To launch at login: System Settings > General > Login Items, add Kyber."
