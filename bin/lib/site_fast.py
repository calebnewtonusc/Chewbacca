"""Run browser-use's jev-ultrafast agent on one goal, with Chewbacca's keys.

jev-ultrafast turns the page into a numbered table of controls and asks Jev,
in one request, for both the operation and the element. A text model is
called only when the operation is TYPE_TEXT. Upstream that model is an
OpenAI-compatible endpoint behind TEXT_MODEL_API_KEY; here it is `claude -p`
with the upstream system prompt, so no second key is needed.

The Jev key comes from bin/lib/jev.py (environment, else the Keychain) and is
set only in this process. browser-harness telemetry is turned off, because it
would otherwise post the task text to PostHog.

Checked live 2026-09-24 on a headless Chromium: "open the Wikipedia article
about Godel's incompleteness theorems" from the Main Page finished, and most
of its time was the claude call that filled the search box. Set
TEXT_MODEL_API_KEY to use upstream's own text model instead.

Runs inside the jev-ultrafast checkout's environment:
    uv run --project $SITE_FAST_HOME python bin/lib/site_fast.py URL GOAL
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import jev  # noqa: E402

os.environ.setdefault("BH_TELEMETRY", "0")

CLAUDE_CMD = os.environ.get(
    "SITE_FAST_TEXT_CMD",
    # --restricted and an explicit system prompt keep CLAUDE.md out of the
    # call: 419 input tokens and 1.7 s for a one-line prompt on 2026-09-23.
    "claude -p --restricted --strict-mcp-config --tools '' --no-session-persistence "
    "--output-format json --model haiku",
)
# A field value should come back in a few seconds; the flights demo budgets
# its whole run at about 7 s, so a stuck text call must not hang the agent.
TEXT_TIMEOUT_S = 30


def claude_field_text(context: dict):
    """Drop-in for jev_ultrafast.model.field_text: same input, same output
    contract ({"text": str}, at most 2000 characters), different model."""
    from jev_ultrafast import model

    started = time.perf_counter()
    envelope: dict = {}
    argv = shlex.split(CLAUDE_CMD) + ["--system-prompt", model.TEXT_VALUE + "\nReturn only the JSON object."]
    try:
        out = subprocess.run(argv, input=json.dumps(context), capture_output=True, text=True,
                             timeout=TEXT_TIMEOUT_S)
        envelope = json.loads(out.stdout)
        match = re.search(r"\{.*\}", envelope.get("result") or "", re.S)
        output = json.loads(match.group(0)) if match else {}
    except (OSError, subprocess.TimeoutExpired, ValueError):
        output = {}
    value = output.get("text") if isinstance(output, dict) else None
    if not isinstance(value, str) or not value.strip() or len(value) > 2000:
        raise ValueError("Text helper returned no valid field value; nothing typed.")
    return value, {
        "model": "claude-haiku",
        "latency_ms": round((time.perf_counter() - started) * 1000),
        "usage": {"cost_usd": envelope.get("total_cost_usd")},
    }


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: site-fast URL GOAL", file=sys.stderr)
        return 2
    key = jev.api_key()
    if not key or not jev.allowed():
        print("site-fast: no Jev key (TYPESAFE_API_KEY or the Keychain entry)", file=sys.stderr)
        return 1
    os.environ["TYPESAFE_API_KEY"] = key

    from jev_ultrafast import agent as agent_module
    from jev_ultrafast import Agent

    if not os.environ.get("TEXT_MODEL_API_KEY"):
        agent_module.field_text = claude_field_text

    url, goal = argv[0], " ".join(argv[1:])
    state = None
    with Agent(url, goal) as agent:
        for state in agent.run():
            last = state["history"][-1] if state["history"] else {}
            print(json.dumps({"ms": state["elapsed_ms"], "status": state["status"],
                              "action": last.get("action"), "text": last.get("text")}), flush=True)
    if state is None:
        return 1
    print(json.dumps({"final": state["status"], "url": state["page"]["url"],
                      "actions": len(state["history"]), "ms": state["elapsed_ms"]}))
    return 0 if state["status"] == "done" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
