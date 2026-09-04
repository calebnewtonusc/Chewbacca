#!/usr/bin/env bash
# Break the "re-grant permissions for every host app" wall, permanently.
#
# A CLI has no TCC identity, so macOS attributes its requests to whatever .app
# launched it: grant Terminal, and it breaks in VS Code; grant VS Code, and it
# breaks in cron. This builds Chewbacca into its own signed .app with its own bundle
# ID, so the grant attaches to CHEWBACCA ITSELF and survives every host. Grant it
# once, ever. It works from Terminal, VS Code, Cursor, launchd, anywhere.
#
# What it does NOT do: eliminate the first grant. Nothing can, short of MDM.
# macOS still shows the toggle once. It never has to be redone after that.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$HOME/Applications/Chewbacca.app}"
BUNDLE_ID="ai.chewie.control"
IDENTITY="${CHEWIE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -m1 -oE '"[^"]+"' | tr -d '"')}"

echo "==> Building $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# The launcher: an app double-clickable identity that forwards to the CLI, or
# runs a command passed by an automation. TCC sees THIS bundle.
cat > "$APP/Contents/MacOS/chewie-app" <<LAUNCH
#!/bin/bash
export CHEWIE_ROOT="$ROOT"
export PATH="\$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:\$PATH"
exec "$ROOT/bin/chewie" "\$@"
LAUNCH
chmod +x "$APP/Contents/MacOS/chewie-app"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>chewie-app</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Chewbacca</string>
  <key>CFBundleDisplayName</key><string>Chewbacca</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Chewbacca controls your apps on your behalf.</string>
  <key>NSSystemAdministrationUsageDescription</key><string>Chewbacca automates your Mac on your behalf.</string>
</dict>
</plist>
PLIST

cat > "$APP/Contents/entitlements.plist" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.automation.apple-events</key><true/>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
</plist>
ENT

if [ -n "$IDENTITY" ]; then
  echo "==> Signing as: $IDENTITY"
  codesign --force --deep --options runtime \
    --entitlements "$APP/Contents/entitlements.plist" \
    --sign "$IDENTITY" "$APP"
  codesign -dv "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier" || true
else
  echo "==> No Developer identity found; ad-hoc signing (works locally, will not notarize)"
  codesign --force --deep --sign - "$APP"
fi

echo
echo "Built $APP with bundle id $BUNDLE_ID"
echo
echo "Grant it ONCE, and it never has to be re-granted for any host again:"
echo "  System Settings > Privacy & Security > Accessibility  -> add $APP"
echo "  System Settings > Privacy & Security > Full Disk Access -> add $APP"
echo
echo "Then route automation through it instead of the bare CLI:"
echo "  $APP/Contents/MacOS/chewie-app see --app Safari"
echo "  ln -sf \"$APP/Contents/MacOS/chewie-app\" ~/.local/bin/chewie-app"
