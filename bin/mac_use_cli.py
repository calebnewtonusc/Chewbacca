"""CLI entry point for macOS-use. Not upstream: see ~/.local/bin/mac-use.

Upstream ships examples/try.py, which hardcodes a greeting agent and then blocks
on input(). That cannot be scripted or called from an agent, so this exposes the
same Agent loop as one non-interactive command.
"""

import argparse
import asyncio
import os
import shutil
import sys

from pydantic import SecretStr

from mlx_use import Agent
from mlx_use.controller.service import Controller

# Cheapest-first, matching the order upstream's example probes them in. Each
# entry is (env var, factory) so an unset key costs nothing to check.
PROVIDERS = (
    ("GEMINI_API_KEY", "google", "gemini-2.0-flash-exp"),
    ("OPENAI_API_KEY", "openai", "gpt-4o"),
    ("ANTHROPIC_API_KEY", "anthropic", "claude-sonnet-4-20250514"),
)

# The key-free fallback. Claude Code is already installed and already logged in,
# so the agent can run with no provider account at all. It is slower and costs
# more per step than a direct API call, which is why a real key still wins.
CLI_PROVIDER = "claude-cli"


def build_claude_cli(model="sonnet"):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from mac_use_claude import ClaudeCLIChatModel

    return ClaudeCLIChatModel(model=model)


def build_llm(preferred=None):
    if preferred == CLI_PROVIDER:
        return build_claude_cli(), CLI_PROVIDER
    for env, name, model in PROVIDERS:
        if preferred and name != preferred:
            continue
        key = os.getenv(env)
        if not key:
            continue
        if name == "google":
            from langchain_google_genai import ChatGoogleGenerativeAI

            return ChatGoogleGenerativeAI(model=model, api_key=SecretStr(key)), name
        if name == "openai":
            from langchain_openai import ChatOpenAI

            return ChatOpenAI(model=model, api_key=SecretStr(key)), name
        from langchain_anthropic import ChatAnthropic

        return ChatAnthropic(model=model, api_key=SecretStr(key)), name
    if preferred:
        return None, None
    # No key anywhere. Fall back to the CLI rather than refusing to run.
    if shutil.which(os.environ.get("CLAUDE_PATH", "claude")):
        return build_claude_cli(), CLI_PROVIDER
    return None, None


def main():
    p = argparse.ArgumentParser(
        prog="mac-use",
        description="Drive any macOS app from one natural-language task.",
    )
    p.add_argument("task", nargs="+", help="what the agent should do")
    p.add_argument("--steps", type=int, default=25, help="max agent steps (default 25)")
    p.add_argument(
        "--actions", type=int, default=4, help="max actions per step (default 4)"
    )
    p.add_argument("--failures", type=int, default=5, help="max failures (default 5)")
    p.add_argument("--vision", action="store_true", help="send screenshots to the model")
    p.add_argument(
        "--provider",
        choices=[name for _, name, _ in PROVIDERS] + [CLI_PROVIDER],
        help="force a provider instead of first key found, then the Claude CLI",
    )
    args = p.parse_args()

    llm, provider = build_llm(args.provider)
    if llm is None:
        names = ", ".join(env for env, _, _ in PROVIDERS)
        print(
            f"mac-use: no API key ({names}) and no claude CLI on PATH.",
            file=sys.stderr,
        )
        return 2

    task = " ".join(args.task)
    print(f"mac-use: {provider}, {args.steps} steps max", file=sys.stderr)

    agent = Agent(
        task=task,
        llm=llm,
        controller=Controller(),
        use_vision=args.vision,
        max_actions_per_step=args.actions,
        max_failures=args.failures,
    )
    asyncio.run(agent.run(max_steps=args.steps))
    return 0


if __name__ == "__main__":
    sys.exit(main())
