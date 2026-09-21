#!/usr/bin/env bash
# Make a signing identity that stays put, so macOS permissions survive a rebuild.
#
# Ad-hoc signing has one cost and this script is how you stop paying it. macOS
# does not store "BobHUD may use Accessibility"; it stores a code requirement,
# and an ad-hoc signature with no team identifier gives it nothing to name
# except the binary's own hash. Every rebuild is a new hash. The row keeps
# saying allowed, the switch in System Settings keeps reading as on, and the
# app is refused: on 2026-09-21 the grant pinned
# 2efeddb7a49900f9f1d0d2a27e1ea2298b806558 at 05:13:59 and the bundle rebuilt
# at 13:40:12 as a4246cb7228c1b8662ccd2972f304ce75777334b, so every click of
# the dictation bubble reopened a dialogue asking for a permission that had
# already been given.
#
# With a certificate the requirement names the certificate and the bundle
# identifier instead, and both outlive the build. The certificate is
# self-signed and local: it authorises nothing off this Mac, it is not a
# Developer ID, and it does not let the app be distributed.
#
# Run once. It needs an administrator password for one step, because trusting
# a certificate for code signing writes to the system keychain and only a
# person can authorise that.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="$(cd .. && pwd)"
NAME="Chewbacca Local Signing"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Identity \"$NAME\" is already in the keychain."
else
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT

  # 1.2.840.113635.100.6.1.13 is Apple's code-signing extension. Without it
  # the certificate is a certificate and not an identity `codesign` will use.
  cat > "$WORK/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Chewbacca Local Signing
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
1.2.840.113635.100.6.1.13 = critical,DER:05:00
EOF

  echo "Making the certificate..."
  openssl req -x509 -newkey rsa:2048 -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 7300 -nodes -config "$WORK/cert.cnf" >/dev/null 2>&1
  openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/id.p12" -passout pass: -name "$NAME" >/dev/null 2>&1

  # Only codesign is given the key. macOS may still ask once, the first time it
  # signs, whether codesign may use it; "Always Allow" ends that for good.
  echo "Putting it in your login keychain..."
  security import "$WORK/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "" -T /usr/bin/codesign >/dev/null

  # Trust is what makes it an identity rather than a file. This is the step
  # that needs the password, and the only one.
  echo "Trusting it for code signing (this is the step that asks for your password)..."
  sudo security add-trusted-cert -d -r trustRoot -p codeSign \
    -k /Library/Keychains/System.keychain "$WORK/cert.pem"

  if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "The certificate did not come out valid. Nothing else has changed." >&2
    exit 1
  fi
  echo "Identity \"$NAME\" is ready."
fi

echo
echo "Rebuilding the display so it carries the new signature..."
./scripts/bundle.sh release

echo "Installing it..."
rm -rf /Applications/BobHUD.app
cp -R build/BobHUD.app /Applications/

# The old grant still names a hash that no longer exists anywhere. Clearing it
# is what turns a switch that lies into one honest prompt.
python3 "$REPO/bin/lib/axgrant.py" --repair || true

echo "Restarting it..."
killall BobHUD 2>/dev/null || true
sleep 1
open -a /Applications/BobHUD.app

echo
echo "Ask for a bubble, drop it on a text box, and click it. macOS asks for"
echo "Accessibility once more. Switch BobHUD on, and that answer now holds"
echo "through every rebuild after this one."
