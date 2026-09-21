#!/usr/bin/env python3
"""Read backend health without a model request or credential-file access."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def run(args, timeout=8):
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def item(state, detail):
    return {"state": state, "detail": detail}


def cli_health(name, probe):
    if not shutil.which(name):
        return item("missing", "optional CLI is absent" if name == "codex" else "CLI is absent")
    code, output = run([name, *probe])
    if code == 0:
        if name == "claude":
            try:
                if json.loads(output).get("loggedIn") is not True:
                    return item("unhealthy", "installed; login required")
            except (ValueError, AttributeError):
                return item("installed", "authentication status unavailable")
        return item("healthy", "installed and authenticated; no model call")
    return item("unhealthy", "installed; authentication check failed or timed out")


def health(probe_browser=False):
    runtime = Path(os.environ.get("MACOS_USE_HOME", str(Path.home() / "Projects/macOS-use"))).expanduser()
    result = {
        "claude": cli_health("claude", ["auth", "status", "--json"]),
        "codex": cli_health("codex", ["login", "status"]),
        "chatgpt_bridge": item("installed" if shutil.which("chatgpt-tab") else "missing", "chatgpt-tab launcher on PATH"),
        "chrome": item("installed" if any(p.exists() for p in [Path("/Applications/Google Chrome.app"), Path.home() / "Applications/Google Chrome.app"]) else "missing", "Google Chrome application"),
        "macos_use": item("installed" if os.access(runtime / ".venv/bin/python", os.X_OK) else "missing", "macOS-use runtime venv"),
        "provider_cli": item("installed" if (ROOT / "bin/mac_use_cli.py").is_file() else "missing", "Chewbacca-owned provider CLI"),
    }
    shims = [n for n in ("mac_use_cli.py", "mac_use_claude.py", "mac_use_chatgpt.py") if (runtime / n).exists()]
    result["runtime_ownership"] = item("unhealthy" if shims else "healthy", "duplicated provider shims: " + ", ".join(shims) if shims else "no duplicated provider shims")
    if (runtime / ".git").exists():
        code, output = run(["git", "-C", str(runtime), "status", "--porcelain"])
        result["runtime_git"] = item("healthy" if code == 0 and not output.strip() else "unhealthy", "upstream working tree clean" if code == 0 and not output.strip() else "upstream working tree dirty or unreadable")
    if probe_browser and shutil.which("chatgpt-tab"):
        code, output = run(["chatgpt-tab", "status", "--json", "--timeout", "5"], timeout=8)
        try:
            status = json.loads(output)
        except ValueError:
            status = {}
        if not isinstance(status, dict):
            status = {}
        healthy = code == 0 and status.get("healthy") is True
        result["chatgpt_bridge"] = item("healthy" if healthy else "unhealthy", "reachable idle signed-in tab; Apple Events JavaScript works" if healthy else str(status.get("detail") or "no usable tab; check Chrome, login, and Allow JavaScript from Apple Events"))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--probe-browser", action="store_true")
    parser.add_argument("--lines", action="store_true")
    args = parser.parse_args()
    result = health(args.probe_browser)
    if args.lines:
        for name, value in result.items():
            print(f"{name}|{value['state']}|{value['detail'].replace(chr(10), ' ').replace('|', '/')} ")
    else:
        print(json.dumps(result))


if __name__ == "__main__":
    main()
