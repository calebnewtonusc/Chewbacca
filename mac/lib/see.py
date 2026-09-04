#!/usr/bin/env python3
"""Layer 3 with automatic escalation, done right.

The loop the shell version got wrong: read the tree, and only if the tree is
genuinely empty on a real window force the Electron attribute and retry. A
"no window" error is not an empty tree and must not be reported as a canvas.
"""
import json, os, subprocess, sys

LIB = os.path.dirname(os.path.abspath(__file__))


def snapshot(app):
    cmd = ["agent-desktop", "snapshot", "-i"]
    if app:
        cmd += ["--app", app]
    try:
        raw = subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return {"ok": False, "error": {"code": "DRIVER", "message": str(e)}}
    try:
        return json.loads(raw or "{}")
    except json.JSONDecodeError:
        return {"ok": False, "error": {"code": "PARSE", "message": raw[:200]}}


def force_ax(app):
    subprocess.run(["osascript", "-l", "JavaScript", f"{LIB}/force-ax.js", app],
                   capture_output=True, timeout=10)


def refs(d):
    return (d.get("data") or {}).get("ref_count", 0) or 0


def main():
    app = None
    force = False
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--app":
            app = args[i + 1]; i += 2
        elif args[i] == "--force-ax":
            force = True; i += 1
        else:
            i += 1

    if force and app:
        force_ax(app)
        import time; time.sleep(0.4)

    d = snapshot(app)

    if not d.get("ok"):
        err = d.get("error", {})
        code = err.get("code", "UNKNOWN")
        if code == "WINDOW_NOT_FOUND":
            print(f"# {app or 'app'} is running but has no open window.", file=sys.stderr)
            print(f"# open one first: chewie run 'tell application \"{app}\" to activate'", file=sys.stderr)
        else:
            print(f"# snapshot failed: {code} {err.get('message','')}", file=sys.stderr)
        print(json.dumps(d))
        sys.exit(1)

    n = refs(d)
    # A near-empty tree on a real window is almost always an Electron app that has
    # not built its tree yet. Force it and retry, but only when we have an app to
    # target the attribute at.
    if not force and n < 5 and app:
        force_ax(app)
        import time; time.sleep(0.4)
        d2 = snapshot(app)
        if d2.get("ok") and refs(d2) > n:
            print(f"# auto-enabled the Electron tree ({n} -> {refs(d2)} refs)", file=sys.stderr)
            d, n = d2, refs(d2)

    print(json.dumps(d))

    if n < 3:
        print(f"# tree still empty after the Electron fix. This is a canvas app "
              f"(Figma, a game, video): the accessibility tree cannot see it.", file=sys.stderr)
        print(f"# for web content use: chewie web read", file=sys.stderr)
        print(f"# for a real canvas use: chewie shot --app {app or '...'}", file=sys.stderr)


if __name__ == "__main__":
    main()
