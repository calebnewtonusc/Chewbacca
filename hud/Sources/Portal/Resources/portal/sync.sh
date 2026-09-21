#!/bin/bash
# Re-vendor the portal core from OpenVision. Run from anywhere.
#
# The HUD must not resolve dependencies at launch, so the core is copied in
# rather than imported. This script is the only sanctioned way to update it,
# and it records the commit so the copy is never mystery code.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git clone --depth 1 https://github.com/calebnewtonusc/OpenVision "$tmp/ov" >/dev/null 2>&1
rev="$(git -C "$tmp/ov" rev-parse --short HEAD)"

for f in types.ts circle.ts portal-state.ts pinch.ts gestures.ts skeleton.ts; do
  cp "$tmp/ov/lib/openvision/core/$f" "$here/vendor/$f"
  echo "  $f"
done

# Keep the recorded commit honest. A vendored copy whose README claims the
# wrong revision is worse than one with no README.
sed -i '' "s/at commit \`[0-9a-f]*\`/at commit \`$rev\`/" "$here/vendor/README.md"
echo "vendored from OpenVision @ $rev"
