"""A LangChain chat model backed by the local Claude CLI, so mac-use needs no API key.

macOS-use expects a LangChain model and calls
`llm.with_structured_output(AgentOutput, include_raw=True)`, which normally
requires a provider with tool calling. Claude Code is already installed and
already authenticated, so this shells out to `claude -p` and does the structured
part by asking for JSON and parsing it back.

Two things the CLI does that a raw API call does not:

- It loads the user's `~/.claude/CLAUDE.md`, so the reply can carry a preamble
  the instructions ask for. Never assume the whole response is JSON; find the
  JSON inside it. That is what `extract_json` is for.
- It bills each call as a full session, and a large CLAUDE.md is re-cached every
  time. Expect roughly ten cents per agent step, so an agent run costs real
  money. Set a provider API key instead when running long tasks.

`--bare` would skip CLAUDE.md and cut that cost, but it also refuses OAuth and
keychain auth and demands ANTHROPIC_API_KEY, which defeats the purpose here.
"""

from __future__ import annotations

import json
import os
import subprocess
from typing import Any, Dict, List, Optional, Type

from langchain_core.callbacks import CallbackManagerForLLMRun
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import AIMessage, BaseMessage
from langchain_core.outputs import ChatGeneration, ChatResult
from langchain_core.runnables import Runnable, RunnableLambda
from pydantic import BaseModel

DEFAULT_TIMEOUT = 300


def extract_json(text: str) -> Optional[dict]:
    """Pull the first complete JSON object out of arbitrary prose.

    Brace matching rather than a regex, because the agent's own output contains
    nested objects and braces inside string values.
    """
    depth = 0
    start = -1
    in_str = False
    esc = False
    for i, ch in enumerate(text):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                try:
                    return json.loads(text[start : i + 1])
                except ValueError:
                    start = -1
    return None


class ClaudeCLIChatModel(BaseChatModel):
    """Minimal chat model that calls the `claude` binary in print mode."""

    model: str = "sonnet"
    timeout: int = DEFAULT_TIMEOUT
    binary: str = os.environ.get("CLAUDE_PATH", "claude")

    @property
    def _llm_type(self) -> str:
        return "claude-cli"

    def _call_cli(self, prompt: str) -> str:
        cmd = [self.binary, "-p", "--model", self.model, "--output-format", "json"]
        try:
            proc = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=self.timeout,
                # Run from a neutral directory: a project CLAUDE.md would other-
                # wise load on top of the user one and change the answer.
                cwd=os.path.expanduser("~"),
            )
        except FileNotFoundError as exc:
            raise RuntimeError(
                f"claude CLI not found at {self.binary!r}. Install Claude Code or set CLAUDE_PATH."
            ) from exc
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(f"claude CLI timed out after {self.timeout}s") from exc

        if proc.returncode != 0:
            raise RuntimeError(f"claude CLI failed ({proc.returncode}): {proc.stderr[:400]}")

        envelope = extract_json(proc.stdout)
        if envelope and "result" in envelope:
            return envelope["result"]
        return proc.stdout

    @staticmethod
    def _flatten(messages: List[BaseMessage]) -> str:
        parts = []
        for m in messages:
            role = getattr(m, "type", "human")
            content = m.content
            if isinstance(content, list):
                # Vision turns arrive as content blocks; keep only the text.
                content = " ".join(
                    b.get("text", "") for b in content if isinstance(b, dict)
                )
            parts.append(f"[{role}]\n{content}")
        return "\n\n".join(parts)

    def _generate(
        self,
        messages: List[BaseMessage],
        stop: Optional[List[str]] = None,
        run_manager: Optional[CallbackManagerForLLMRun] = None,
        **kwargs: Any,
    ) -> ChatResult:
        text = self._call_cli(self._flatten(messages))
        return ChatResult(generations=[ChatGeneration(message=AIMessage(content=text))])

    def with_structured_output(
        self,
        schema: Type[BaseModel],
        *,
        include_raw: bool = False,
        **kwargs: Any,
    ) -> Runnable:
        """Ask for the schema as JSON and parse it back.

        LangChain's default implementation routes through tool calling, which the
        CLI does not expose. macOS-use passes include_raw=True and reads
        `raw`, `parsed`, and `parsing_error`, so return that shape exactly.
        """
        model = self

        def invoke(messages: Any) -> Any:
            if isinstance(messages, BaseMessage):
                messages = [messages]
            prompt = model._flatten(list(messages))
            prompt += (
                "\n\n[output contract]\n"
                "Reply with ONE JSON object matching this schema. No markdown "
                "fence, no commentary after it.\n"
                + json.dumps(schema.model_json_schema())
            )
            text = model._call_cli(prompt)
            raw = AIMessage(content=text)
            data = extract_json(text)
            if data is None:
                err = ValueError("no JSON object found in the CLI response")
                if include_raw:
                    return {"raw": raw, "parsed": None, "parsing_error": err}
                raise err
            try:
                parsed = schema.model_validate(data)
            except Exception as exc:  # a schema mismatch must not kill the run
                if include_raw:
                    return {"raw": raw, "parsed": None, "parsing_error": exc}
                raise
            if include_raw:
                return {"raw": raw, "parsed": parsed, "parsing_error": None}
            return parsed

        return RunnableLambda(invoke)
