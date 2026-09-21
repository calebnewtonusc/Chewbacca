#!/bin/bash
# Build Portal.app: the Doctor Strange portal on the HUD glass.
#
# WHY A BUNDLE AND NOT `swift run`. macOS will not grant camera access to a
# bare executable. There is no Info.plist to read a usage description from,
# so the process is not denied, it is KILLED on the first frame. That failure
# looks exactly like a crash with no message, and it cost an evening on this
# repo already (commit 6284ab4, the HUD dying on launch for a missing key).
#
# WHY THE DESIGNATED REQUIREMENT IS PINNED. An ad-hoc signature's default
# requirement is the binary's own hash, and TCC keys the camera grant to that
# requirement. Every rebuild then produces a new hash, tccd logs "Failed to
# match existing code requirement", and the grant silently evaporates: you
# approve the camera, change one line, rebuild, and the portal is dark again
# with nothing in any log you would think to read. Pinning to the bundle
# identifier is what a real certificate would do, without needing one.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP="build/Portal.app"
CONFIG="${CONFIG:-release}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Building Portal ($CONFIG)..."
swift build -c "$CONFIG" --product Portal >/dev/null
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
cp "$BIN/Portal" "$APP/Contents/MacOS/Portal"

# The web layer goes in Contents/Resources, the ordinary place, NOT as
# SwiftPM's generated .bundle. That bundle ships without an Info.plist, so
# codesign refuses the whole app with "bundle format unrecognized" and the
# signature is skipped, which quietly takes the pinned designated requirement
# with it and puts the camera grant back to evaporating on every rebuild.
cp -R Sources/Portal/Resources/portal "$APP/Contents/Resources/portal"
[ -f "$APP/Contents/Resources/portal/portal.js" ] \
  || { echo "error: portal.js missing. Run: cd Sources/Portal/Resources/portal && npx esbuild portal.entry.ts --bundle --format=iife --target=es2020 --outfile=portal.js" >&2; exit 1; }

BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>Portal</string>
  <key>CFBundleDisplayName</key>     <string>Portal</string>
  <key>CFBundleIdentifier</key>      <string>dev.bobthebuilder.portal</string>
  <key>CFBundleExecutable</key>      <string>Portal</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>0.1.0</string>
  <key>CFBundleVersion</key>         <string>$BUILD</string>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <key>LSUIElement</key>             <true/>
  <key>NSHighResolutionCapable</key> <true/>
  <!-- Without this the process is killed on the first frame rather than
       being denied, which reads as an unexplained crash. -->
  <key>NSCameraUsageDescription</key>
  <string>Portal watches for one gesture: pinch your fingers and draw a circle in the air. Frames are read on this Mac by Apple's Vision framework, never recorded, and never leave the machine.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier dev.bobthebuilder.portal \
  --requirements '=designated => identifier "dev.bobthebuilder.portal"' "$APP" 2>/dev/null \
  || echo "  (unsigned; it will still run)"

echo "Built $APP"
echo
echo "  open $APP      pinch, draw a circle. Esc quits."
