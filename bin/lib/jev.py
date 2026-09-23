"""TypeSafe's Jev: typed judgments over HTTP, fast enough to sit in a voice turn.

One call, `ask(state, questions)`, returning the `answers` map or None. None
means "no judgment": no key, a timeout, a non-200, a body that is not JSON.
Callers treat None exactly like an unconfigured classifier, so Jev being down
never costs more than the rules already cost.

Docs: https://docs.typesafe.ai/api.md
"""
import json
import os
import subprocess
import urllib.error
import urllib.request

URL = "https://api.typesafe.ai/v1/systemone"
MODEL = os.environ.get("TYPESAFE_MODEL", "jev-latest")
# Measured 2026-09-23 from this Mac: 0.18 to 0.32 s per single-question call.
# Ten times the worst of those still leaves the router's 3 s budget intact.
TIMEOUT_S = 2.5

_key: str | None = None


def api_key() -> str | None:
    """TYPESAFE_API_KEY from the environment, else the login Keychain.

    hud-listen runs under launchd and does not inherit a shell, so the
    Keychain entry (service TYPESAFE_API_KEY) is the path that actually
    fires in production. Looked up once per process.
    """
    global _key
    if _key is None:
        _key = os.environ.get("TYPESAFE_API_KEY", "")
        if not _key:
            try:
                out = subprocess.run(
                    ["security", "find-generic-password", "-s", "TYPESAFE_API_KEY", "-w"],
                    capture_output=True, text=True, timeout=2.0,
                )
                _key = out.stdout.strip() if out.returncode == 0 else ""
            except (OSError, subprocess.TimeoutExpired):
                _key = ""
    return _key or None


def ask(state, questions: dict, timeout: float = TIMEOUT_S) -> dict | None:
    key = api_key()
    if not key:
        return None
    body = json.dumps({"state": state, "model": MODEL, "questions": questions}).encode()
    req = urllib.request.Request(URL, data=body, method="POST", headers={
        "Authorization": f"Bearer {key}", "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            answers = json.loads(resp.read()).get("answers")
    except (OSError, urllib.error.URLError, ValueError):
        return None
    return answers if isinstance(answers, dict) else None
