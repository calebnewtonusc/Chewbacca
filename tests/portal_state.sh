#!/usr/bin/env bash
# Opening and closing a portal. Builds the real reducer each run.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v node >/dev/null || { echo "node absent"; exit 0; }
npx --yes esbuild "$ROOT/hud/Sources/Portal/Resources/portal/vendor/portal-state.ts" \
  --bundle --format=esm --target=es2020 \
  --outfile="$ROOT/tests/.portal-state-under-test.mjs" --log-level=error
node "$ROOT/tests/test_portal_state.mjs"
