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
# Well above the single-question call times seen from this Mac on 2026-09-23
# (kept private under TypeSafe's agreement 2.3(f)), and inside the router's
# 3 s budget.
TIMEOUT_S = 2.5

_key: str | None = None


def api_key() -> str | None:
    """TYPESAFE_API_KEY from the environment, else the login Keychain.

    hud-listen runs under launchd and does not inherit a shell, so the
    Keychain entry (service TYPESAFE_API_KEY) is the path that actually
    fires in production. Looked up once per process.

    Resolved into a local and published once: assigning "" to the cache before
    the Keychain lookup returned made every other thread read "no key", and on
    2026-09-23 that failed 29 of 30 calls in fanout's two-worker pool.
    """
    global _key
    if _key is None:
        key = os.environ.get("TYPESAFE_API_KEY", "")
        if not key:
            try:
                out = subprocess.run(
                    ["security", "find-generic-password", "-s", "TYPESAFE_API_KEY", "-w"],
                    capture_output=True, text=True, timeout=2.0,
                )
                key = out.stdout.strip() if out.returncode == 0 else ""
            except (OSError, subprocess.TimeoutExpired):
                key = ""
        _key = key
    return _key or None


def allowed() -> bool:
    """Whether this process may send anything to Jev at all.

    Jev is a cloud API, so every call is data leaving the machine. Inside an
    Amber user's root (AMBER_ROOT, set by bin/amber-user and amber-mcp) that
    needs the person's own yes, recorded by `amber-user consent <user> jev on`
    in <root>/consent.json. A new user has no file, so Jev is off for them
    until they choose it. Outside any root is the machine owner's own install,
    where having put a TypeSafe key on the machine is the choice.
    """
    root = os.environ.get("AMBER_ROOT")
    if not root:
        return True
    try:
        with open(os.path.join(root, "consent.json")) as f:
            return json.load(f).get("jev") is True
    except (OSError, ValueError, AttributeError):
        return False


def ask(state, questions: dict, timeout: float = TIMEOUT_S) -> dict | None:
    if not allowed():
        return None
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
