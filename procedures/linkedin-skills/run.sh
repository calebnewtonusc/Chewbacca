#!/bin/zsh
# linkedin-skills: list or delete skills on the signed-in LinkedIn profile, in the person's own Chrome.
#
#   run.sh list                      every skill, after scrolling until the list stops growing
#   run.sh delete "Sales" "GitHub"   deletes exactly those, then rereads the list and says what is left
#
# Needs a LinkedIn tab open in the signed-in Chrome profile with "Allow JavaScript from
# Apple Events" on (chrome-js --check). Deleting is public and drops endorsements: show the
# person the names first. There is no "keep only" mode on purpose, so every deletion is named.
emulate -L zsh
C=${0:A:h:h:h}/bin/chrome-js
LIST="https://www.linkedin.com/in/me/details/skills/"
js() { $C --match linkedin.com --eval "$1" 2>/dev/null; }
# 40 polls of 0.25 s. The edit form rendered within about 1 s on every successful run of
# 2026-09-23; 10 s is the point past which it never came.
wait_js() { for i in {1..40}; do [[ $(js "$1") == yes ]] && return 0; sleep 0.25; done; return 1; }
q() { python3 -c 'import json,sys;print(json.dumps("Edit "+sys.argv[1]+" skill"))' "$1"; }

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

# Navigation goes through Chrome, not location.href: after a delete the edit page silently
# ignored location.href (2026-09-23), and every later step then acted on a stale page.
go_list() {
  osascript -e "tell application \"Google Chrome\" to repeat with w in windows
repeat with t in tabs of w
if URL of t contains \"linkedin.com\" then set URL of t to \"$LIST\"
end repeat
end repeat" >/dev/null
  sleep 1; guard_front
  wait_js "document.readyState==='complete'&&location.pathname.endsWith('/details/skills/')&&document.querySelector('a[aria-label^=\"Edit \"]')?'yes':'no'" || return 1
  # The list renders 10 rows and adds more on scroll; scroll until the count stops changing.
  local prev=-1 now=0
  while (( now != prev )); do
    prev=$now; js "window.scrollTo(0,document.body.scrollHeight);1" >/dev/null; sleep 0.6
    now=$(js "document.querySelectorAll('a[aria-label^=\"Edit \"]').length")
  done
}
names() { js "Array.from(document.querySelectorAll('a')).map(e=>e.getAttribute('aria-label')||'').filter(t=>/^Edit .* skill\$/.test(t)).map(t=>t.slice(5,-6)).join('\n')"; }

case $1 in
  list) go_list || { echo "skills page did not load" >&2; exit 1; }; names ;;
  delete)
    shift; (( $# )) || { echo 'usage: run.sh delete "<skill>" ...' >&2; exit 2; }
    for n in "$@"; do
      go_list || { echo "$n: skills page did not load"; continue; }
      # The edit form renders only when opened by a click from the list; loading its URL
      # directly gave an empty page every time (2026-09-23).
      [[ $(js "var a=Array.from(document.querySelectorAll('a')).find(e=>e.getAttribute('aria-label')===$(q "$n"));if(a){a.click();'yes'}else{'no'}") == yes ]] || { echo "$n: not on the list"; continue; }
      wait_js "var b=Array.from(document.querySelectorAll('button')).find(e=>e.innerText.trim()==='Delete skill');if(b){b.click();'yes'}else{'no'}" || { echo "$n: edit form never rendered"; continue; }
      wait_js "var b=Array.from(document.querySelectorAll('button')).find(e=>e.innerText.trim()==='Delete');if(b){b.click();'yes'}else{'no'}" || { echo "$n: no confirm button"; continue; }
      sleep 1.5
    done
    # A click is not a deletion: one run reported "deleted" for a skill still on the list.
    go_list; left=$(names); rc=0
    for n in "$@"; do print -r -- "$left" | grep -qxF "$n" && { echo "STILL THERE: $n"; rc=1; } || echo "deleted: $n"; done
    echo "left: ${left//$'\n'/, }"; exit $rc ;;
  *) sed -n '2,9p' $0 | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
