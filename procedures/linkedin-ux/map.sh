#!/bin/zsh
# Reads every LinkedIn page in pages.tsv in the person's own signed-in Chrome and saves each
# page's controls as JSON. Clicks nothing and saves nothing on LinkedIn.
#
#   map.sh [slug ...]      all pages, or just the named ones
#
# The snapshots hold names of people and message previews, so they go to a private folder,
# $LINKEDIN_UX_DIR (default ~/dev/gavin-context/research/linkedin-ux/pages), never this repo.
emulate -L zsh; zmodload zsh/datetime
HERE=${0:A:h}; C=${HERE:h:h}/bin/chrome-js
OUT=${LINKEDIN_UX_DIR:-$HOME/dev/gavin-context/research/linkedin-ux}/pages; mkdir -p $OUT
js() { $C --match linkedin.com --eval "$1" 2>/dev/null; }
go() { js "location.href='$1';1" >/dev/null; }
# Pages paint in pieces after readyState is complete. Two reads of the control count a
# second apart that agree is the signal it has settled; guessed, never measured.
settle() {
  sleep 1; local prev=-1 now=0 i=0
  for i in {1..12}; do
    [[ $(js "document.readyState") == complete ]] || { sleep 0.5; continue; }
    now=$(js "document.querySelectorAll('a,button,input').length"); (( now == prev && now > 20 )) && return 0
    prev=$now; sleep 1
  done
}
# Chrome must never come to the front: he works on this Mac while this runs (2026-09-23,
# "it keeps bringing the window in front"). Record what is frontmost, and if Chrome ever
# takes it, hand focus back and stop rather than keep stealing it.
FRONT=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
guard_front() {
  [[ $FRONT == "Google Chrome" ]] && return 0
  local now=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
  [[ $now == "Google Chrome" ]] || return 0
  osascript -e "tell application \"$FRONT\" to activate" >/dev/null 2>&1
  echo "stopped: Chrome came to the front; gave focus back to $FRONT" >&2; exit 4
}
while IFS=$'\t' read -r slug url what; do
  (( $# )) && [[ ${@[(Ie)$slug]} -eq 0 ]] && continue
  s=$EPOCHREALTIME; go "$url"; settle
  for i in 1 2; do js "window.scrollTo(0,document.body.scrollHeight);1" >/dev/null; sleep 0.6; done
  js "window.scrollTo(0,0);1" >/dev/null
  guard_front
  $C --match linkedin.com --file $HERE/snap.js > $OUT/$slug.json 2>/dev/null
  printf "%-14s %4s controls  %.1fs  %s\n" $slug "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(len(d["controls"]))' $OUT/$slug.json 2>/dev/null || echo ERR)" $((EPOCHREALTIME-s)) "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["url"])' $OUT/$slug.json 2>/dev/null)"
done < $HERE/pages.tsv
