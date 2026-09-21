#!/usr/bin/env bash
# What the circle detector accepts as a circle. Rebuilds the bundle from the
# real source each run so the test can never drift from what ships.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null || { echo "node absent"; exit 0; }
npx --yes esbuild "$ROOT/hud/Sources/Portal/Resources/portal/vendor/circle.ts" \
  --format=esm --target=es2020 --outfile="$ROOT/tests/.circle-under-test.mjs" \
  --log-level=error
node "$ROOT/tests/test_circle_shapes.mjs"
