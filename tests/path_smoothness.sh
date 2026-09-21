#!/usr/bin/env bash
# No line is ever jagged. Builds the real smoothing from source each run so
# the test cannot drift from what ships.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null || { echo "node absent"; exit 0; }
npx --yes esbuild "$ROOT/hud/Sources/Portal/Resources/portal/vendor/smooth.ts" \
  --format=esm --target=es2020 --outfile="$ROOT/tests/.smooth-under-test.mjs" \
  --log-level=error
node "$ROOT/tests/test_path_smoothness.mjs"
