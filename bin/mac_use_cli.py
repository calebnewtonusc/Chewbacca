"""CLI entry point for macOS-use. Not upstream: see ~/.local/bin/mac-use.

Upstream ships examples/try.py, which hardcodes a greeting agent and then blocks
on input(). That cannot be scripted or called from an agent, so this exposes the
same Agent loop as one non-interactive command.
"""

import argparse
import asyncio
import os
import json
import subprocess
import shutil
import sys
from urllib.parse import urlsplit


# Cheapest-first, matching the order upstream's example probes them in. Each
# entry is (env var, factory) so an unset key costs nothing to check.
PROVIDERS = (
    ("GEMINI_API_KEY", "google", "gemini-2.0-flash-exp"),
    ("OPENAI_API_KEY", "openai", "gpt-4o"),
    ("ANTHROPIC_API_KEY", "anthropic", "claude-sonnet-4-20250514"),
)

# Key-free browser/CLI fallbacks.
#
# chatgpt-web drives the user's existing signed-in ChatGPT browser tab through
# Chewbacca's chatgpt-tab command. Claude CLI remains available as a second
# fallback.
CHATGPT_PROVIDER = "chatgpt-web"
CLI_PROVIDER = "claude-cli"


def chatgpt_binary():
    return os.environ.get("CHATGPT_TAB_PATH") or os.path.join(
        os.path.dirname(os.path.realpath(__file__)), "chatgpt-tab"
    )


def chatgpt_healthy():
    """Probe the browser without submitting a model turn."""
    try:
        result = subprocess.run(
            [chatgpt_binary(), "status", "--json", "--timeout", "5"], capture_output=True, text=True, timeout=15
        )
        state = json.loads(result.stdout)
        parts = urlsplit(state.get("conversation_url", ""))
        return (
            result.returncode == 0 and state.get("healthy") is True
            and parts.scheme == "https" and parts.netloc == "chatgpt.com"
            and parts.path.startswith("/c/") and bool(parts.path[3:])
            and not parts.query and not parts.fragment
        )
    except (OSError, subprocess.TimeoutExpired, ValueError, AttributeError, TypeError):
        return False


def claude_authenticated():
    binary = shutil.which(os.environ.get("CLAUDE_PATH", "claude"))
    if not binary:
        return False
    try:
        result = subprocess.run(
            [binary, "auth", "status", "--json"],
            capture_output=True, text=True, timeout=15,
        )
        return result.returncode == 0 and json.loads(result.stdout).get("loggedIn") is True
    except (OSError, subprocess.TimeoutExpired, ValueError, AttributeError):
        return False


def build_chatgpt_web():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from mac_use_chatgpt import ChatGPTWebChatModel

    return ChatGPTWebChatModel(binary=chatgpt_binary())


def build_claude_cli(model="sonnet"):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from mac_use_claude import ClaudeCLIChatModel

    return ClaudeCLIChatModel(model=model)


def build_llm(preferred=None):
    if preferred == CHATGPT_PROVIDER:
        if shutil.which(chatgpt_binary()):
            return build_chatgpt_web(), CHATGPT_PROVIDER
        return None, None

    if preferred == CLI_PROVIDER:
        return build_claude_cli(), CLI_PROVIDER
    for env, name, model in PROVIDERS:
        if preferred and name != preferred:
            continue
        key = os.getenv(env)
        if not key:
            continue
        from pydantic import SecretStr

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
    # No API key anywhere. Prefer the already-authenticated ChatGPT browser,
    # then retain Claude CLI as the final fallback.
    if chatgpt_healthy():
        return build_chatgpt_web(), CHATGPT_PROVIDER

    if claude_authenticated():
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
        choices=[name for _, name, _ in PROVIDERS] + [CHATGPT_PROVIDER, CLI_PROVIDER],
        help="force a provider instead of automatic provider selection",
    )
    args = p.parse_args()

    llm, provider = build_llm(args.provider)
    if llm is None:
        names = ", ".join(env for env, _, _ in PROVIDERS)
        print(
            (f"mac-use: requested provider {args.provider!r} is unavailable." if args.provider else
             f"mac-use: no API key ({names}), healthy ChatGPT browser session, "
             "or authenticated Claude CLI. Open a signed-in ChatGPT tab or run claude auth login."),
            file=sys.stderr,
        )
        return 2

    from mlx_use import Agent
    from mlx_use.controller.service import Controller
    from ApplicationServices import AXIsProcessTrusted

    if not AXIsProcessTrusted():
        print("mac-use: macOS Accessibility access is not granted to this launch host. "
              "Enable the host in System Settings > Privacy & Security > Accessibility, "
              "then restart it. No model task was started.", file=sys.stderr)
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
