#!/bin/bash
# page-render must render the same page to the same pixels, every run.
#
# WHY. The whole point of the tool is that page time is fake: a screen recording
# of the Kyber demo drops frames and captures whatever the laptop was doing. If
# any one of the three clocks leaks back to real time (timers, rAF, or a CSS
# animation left on the compositor), two renders of one page stop matching, and
# nothing else would notice: the video still plays.
#
# The fixture drives all three: a setTimeout, a rAF loop that writes
# performance.now(), and an infinite CSS animation. Two preview renders must be
# byte-identical, and frames one second apart must differ, or time never moved.
#
# The rAF loop prints time since its first frame, as real animation code does.
# Absolute performance.now() is not held: Playwright's fake clock sets its
# origin 1 or 2 ms apart on identical runs (measured 2026-09-25, three runs).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 -c "import playwright" 2>/dev/null || { echo "SKIP page_render: python playwright not installed"; exit 0; }
command -v ffmpeg >/dev/null || { echo "SKIP page_render: ffmpeg not installed"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/page.html" <<'HTML'
<!doctype html><html><body style="margin:0;background:#fff;font:40px monospace">
<div id="t">0</div><div id="late">waiting</div>
<div style="width:80px;height:80px;background:#000;animation:m 1.3s linear infinite"></div>
<style>@keyframes m{to{transform:translateX(300px)}}</style>
<script>
setTimeout(() => (document.getElementById("late").textContent = "fired"), 1500);
let t0; requestAnimationFrame(function f(now) { t0 ??= now; document.getElementById("t").textContent = Math.round(now - t0); requestAnimationFrame(f); });
</script></body></html>
HTML

render() {
  "$ROOT/bin/page-render" "file://$TMP/page.html" "$TMP/$1.png" --size 400x300 \
    --preview 1 --duration 2 --settle 0.2 2>&1 | sed -n 's/.*frames in \(.*\))$/\1/p'
}
A="$(render a)"
B="$(render b)"
fail=0
[ -n "$A" ] && [ -n "$B" ] || { echo "FAIL page_render: no frames written"; exit 1; }
for f in 0000 0001 0002; do
  cmp -s "$A/$f.png" "$B/$f.png" || { echo "FAIL page_render: frame $f differs between two runs"; fail=1; }
done
cmp -s "$A/0000.png" "$A/0001.png" && { echo "FAIL page_render: page time did not advance"; fail=1; }
[ "$fail" = 0 ] && rm -rf "$A" "$B" || echo "frames kept: $A $B"
[ "$fail" = 0 ] && echo "ok page_render: two renders identical, time advances"
exit "$fail"
