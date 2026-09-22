#!/bin/bash
H=~/Desktop/2026-Code/projects/chewbacca/.claude/hooks/load-guard.sh
pass=0; fail=0
t() { # name, expected_exit, command
  out=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$3")" | bash "$H" 2>/dev/null)
  rc=$?
  if [ "$rc" = "$2" ]; then echo "  ok   $1 (exit $rc)"; pass=$((pass+1));
  else echo "  FAIL $1 (exit $rc, wanted $2)"; fail=$((fail+1)); fi
}
echo "SHOULD BLOCK (exit 2):"
t "xargs -P 6 whisper"        2 'cat ids.txt | xargs -P 6 -I{} yt-transcript {}'
t "parallel -j 8 ffmpeg"      2 'parallel -j 8 ffmpeg -i {} out.mp4 ::: *.mov'
t "unbounded & loop"          2 'for f in *.wav; do whisper "$f" & done'
t "xargs -P 4 mlx_whisper"    2 'ls | xargs -P 4 python3 -c "import mlx_whisper"'
echo "SHOULD PASS (exit 0):"
t "serial + nice 19"          0 'for x in a b; do nice -n 19 yt-transcript "$x"; done'
t "single whisper"            0 'yt-transcript abc123 --timestamps'
t "xargs -P 6, not heavy"     0 'cat urls.txt | xargs -P 6 -I{} curl -s {}'
t "grepping for whisper"      0 'grep -rn "whisper" notes/'
t "killing whisper"           0 'pkill -9 -f mlx_whisper'
t "writing about it"          0 'echo "we ran ffmpeg in parallel and it was bad" >> notes.md'
t "non-Bash tool"             0 'ignored'
echo; echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
