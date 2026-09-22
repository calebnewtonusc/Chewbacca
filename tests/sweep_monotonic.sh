#!/usr/bin/env bash
# The oscillating gap: sweep is signed, so hand noise walks it backwards.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null || { echo "node absent"; exit 0; }
npx --yes esbuild "$ROOT/hud/Sources/Portal/Resources/portal/vendor/circle.ts" \
  --bundle --format=esm --target=es2020 --outfile="$ROOT/tests/.circle-under-test.mjs" \
  --log-level=error
echo "how far the drawn extent walks backwards, per frame:"
node "$ROOT/tests/test_sweep_monotonic.mjs"
