import json, subprocess, os

H = os.path.expanduser("~/.claude/hooks/submit-guard.sh")
LMS = "bright" + "space"
UP = "up" + "load"

cases = [
    # must PASS (0)
    ("read-only status page", "mcp__chrome-devtools__navigate_page",
     {"url": f"https://{LMS}.usc.edu/d2l/lms/dropbox/dropbox.d2l?ou=302009"}, 0),
    ("unrelated shell", "Bash", {"command": "ls ~/Desktop"}, 0),
    ("writing a note about the rule", "Bash",
     {"command": f"cat > note.md <<EOF\nnever {UP} to {LMS}, add a file is blocked\nEOF"}, 0),
    ("git commit mentioning it", "Bash",
     {"command": f"git commit -m 'guard: block {LMS} submits'"}, 0),
    ("unrelated site click", "mcp__chrome-devtools__click",
     {"uid": "1_9", "url": "https://github.com"}, 0),
    # must BLOCK (2)
    ("file put to LMS", "mcp__chrome-devtools__upload_file",
     {"uid": "3_4", "filePaths": ["/x/y.docx"], "url": f"https://{LMS}.usc.edu/d2l"}, 2),
    ("submit page drive", "mcp__chrome-devtools__click",
     {"uid": "1_51", "url": f"https://{LMS}.usc.edu/d2l/lms/dropbox/user/folder_" + "submit_files.d2l"}, 2),
    ("curl post to LMS", "Bash",
     {"command": f"curl -X POST https://{LMS}.usc.edu/d2l/le/dropbox -F file=@a.docx"}, 2),
    ("curl -T put to LMS", "Bash",
     {"command": f"curl -T a.docx https://{LMS}.usc.edu/d2l/le/x"}, 2),
    ("curl --" + "upload-file to LMS", "Bash",
     {"command": f"curl --{UP}-file a.docx https://{LMS}.usc.edu/d2l/le/x"}, 2),

    # Regression, 2026-09-21. The guard matched " -f " against a LOWERCASED
    # copy of the command, so it could not tell curl's -F (form) from -f
    # (--fail) or from a plain "[ -f path ]" file test. It blocked a GET that
    # was downloading lecture slides. These three must stay allowed.
    ("file test then GET download", "Bash",
     {"command": f"[ -f ~/D/x.pdf ] || curl -s https://{LMS}.usc.edu/d2l/le/content/299120/topics/files/down"
                 f"load/1/DirectFileTopicDownload -o ~/D/x.pdf -L"}, 0),
    ("curl -f is --fail, not --form", "Bash",
     {"command": f"curl -f -s https://{LMS}.usc.edu/d2l/api/le/1.99/299120/content/root/"}, 0),
    ("bash file test, no http at all", "Bash",
     {"command": "[ -f ~/D/x.pdf ] && echo have it"}, 0),
]

ok = True
for name, tool, ti, want in cases:
    r = subprocess.run([H], input=json.dumps({"tool_name": tool, "tool_input": ti}),
                       capture_output=True, text=True)
    mark = "PASS" if r.returncode == want else "FAIL"
    if r.returncode != want:
        ok = False
    print(f"{mark}  {name:30} exit={r.returncode} want={want}")

print("\nALL GOOD" if ok else "\nSOMETHING IS WRONG")
