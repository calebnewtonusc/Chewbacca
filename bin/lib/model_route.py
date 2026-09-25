"""Classify a Claude Code prompt into the model router's task classes by Jev.

After 0xNatoshi/jev-codex-router: one typed Choice per prompt instead of a
model call. claude-model-router-hook decides confident prompts by keyword and
sends the rest to `claude -p ... --model haiku`, bounded at 8 s. That fallback
loads the whole CLAUDE.md, so it was slow and it rarely answered; see
SLOW_FALLBACK below for the measurement. This answers the same question in a
fraction of a second and is what `model-route` and the hook print.

The classes and targets are the router's own (router/taxonomy.py CLASSES and
config.py DEFAULTS), repeated here so this never imports a plugin's cache.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import jev  # noqa: E402

TARGETS = {
    "mechanical": ("haiku", None),
    "implementation": ("opus", "medium"),
    "debugging": ("opus", "high"),
    "architecture": ("opus", "xhigh"),
    "extreme": ("opus", "max"),
}
CRITERIA = {
    "mechanical": "git operations, renames, formatting, lint, file moves, version bumps, quick lookups",
    "implementation": "writing or editing code, building a feature, a component, an API, or tests",
    "debugging": "diagnosing a failure, an error, a flaky test, a regression, a stack trace",
    "architecture": "design decisions, tradeoffs, redesigns, deep analysis across many files",
    "extreme": "multi-system migrations, codebase-wide rewrites, long-horizon plans, design docs",
    "none": "not a task for a coding agent: conversation, a question about the person's life, unclear",
}
# The same 1500 the router's CLI fallback sends, so both judge the same text.
SNIPPET = 1500
# Guessed, never measured: below this the router's own heuristic is as good.
FLOOR = 0.5
TIMEOUT_S = 3.0


def classify(prompt: str, ask=None) -> dict:
    """{"class", "model", "effort", "confidence"}; class None is an abstain."""
    out = {"class": None, "model": None, "effort": None, "confidence": 0.0}
    if not prompt.strip():
        return out
    if ask is None:
        if not (jev.api_key() and jev.allowed()):
            return out

        def ask(state, questions):
            return jev.ask(state, questions, timeout=TIMEOUT_S, decision="model-route")
    answers = ask({"request": prompt[:SNIPPET]}, {"task": {
        "type": "choice",
        "instructions": {
            "question": "`request` was typed to an AI coding agent. Which kind of work is it?",
            "note": "Judge the work being asked for, not the words used. A short prompt can ask "
                    "for deep work. Choose none when it is not a task at all.",
        },
        "criteria": CRITERIA,
    }})
    answer = (answers or {}).get("task") or {}
    choice = answer.get("choice")
    confidence = float((answer.get("probabilities") or {}).get(choice, 0.0))
    out["confidence"] = round(confidence, 3)
    if choice in TARGETS and confidence >= FLOOR:
        model, effort = TARGETS[choice]
        out.update({"class": choice, "model": model, "effort": effort})
    return out
