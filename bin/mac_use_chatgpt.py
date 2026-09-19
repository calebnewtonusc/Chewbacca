"""LangChain chat model backed by the user's signed-in ChatGPT browser tab.

This mirrors mac_use_claude.py, but instead of calling `claude -p`, it calls
Chewbacca's `chatgpt-tab ask`, which drives the existing ChatGPT browser
session through Chrome.

No OpenAI API key is required.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from typing import Any, List, Optional, Type
from urllib.parse import urlsplit

from langchain_core.callbacks import CallbackManagerForLLMRun
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import AIMessage, BaseMessage
from langchain_core.outputs import ChatGeneration, ChatResult
from langchain_core.runnables import Runnable, RunnableLambda
from pydantic import BaseModel, Field

DEFAULT_TIMEOUT = 300


def json_candidates(text: str):
    """Decode complete objects, resuming after malformed candidates.

    raw_decode handles escaped quotes, nested objects and string braces. Once
    decoded, skip the entire object so its nested members are not separate
    candidate answers. A malformed prefix cannot hide a later valid object.
    """
    decoder = json.JSONDecoder()
    offset = 0
    while True:
        start = text.find("{", offset)
        if start < 0:
            return
        try:
            candidate, end = decoder.raw_decode(text, start)
        except ValueError:
            offset = start + 1
            continue
        offset = end
        if isinstance(candidate, dict):
            yield candidate


def extract_json(text: str) -> Optional[dict]:
    """Return the first complete JSON object from arbitrary prose."""
    return next(json_candidates(text), None)


def validate_response(text: str, schema: Type[BaseModel]):
    error = ValueError("no JSON object found in ChatGPT response")
    for candidate in json_candidates(text):
        try:
            return schema.model_validate(candidate)
        except ValueError as exc:
            error = exc
    raise error


class ChatGPTWebChatModel(BaseChatModel):
    """Minimal LangChain model backed by chatgpt.com in Chrome."""

    timeout: int = DEFAULT_TIMEOUT
    binary: str = Field(default_factory=lambda: os.environ.get("CHATGPT_TAB_PATH") or
                        os.path.join(os.path.dirname(os.path.realpath(__file__)), "chatgpt-tab"))
    repair_attempts: int = Field(default=1, ge=0, le=3)
    conversation: str | None = None

    @property
    def _llm_type(self) -> str:
        return "chatgpt-web"

    def _call_web(self, prompt: str) -> str:
        binary = shutil.which(self.binary) or self.binary

        try:
            if self.conversation is None:
                status = subprocess.run(
                    [binary, "status", "--json", "--timeout", "5"], capture_output=True, text=True,
                    timeout=15, cwd=os.path.expanduser("~"),
                )
                try:
                    state = json.loads(status.stdout)
                    url = state.get("conversation_url", "")
                    parts = urlsplit(url)
                except (ValueError, AttributeError, TypeError) as exc:
                    raise RuntimeError("chatgpt-tab returned an invalid status response") from exc
                if status.returncode or state.get("healthy") is not True:
                    raise RuntimeError("ChatGPT browser session is unavailable or busy")
                if (parts.scheme != "https" or parts.netloc != "chatgpt.com"
                        or not parts.path.startswith("/c/") or not parts.path[3:]
                        or parts.query or parts.fragment):
                    raise RuntimeError(
                        "mac-use needs an existing ChatGPT conversation. Open a saved "
                        "chatgpt.com/c/... conversation before starting the agent."
                    )
                self.conversation = url

            cmd = [
                binary, "ask", "--stdin", "--conversation", self.conversation,
                "--timeout", str(self.timeout),
            ]
            proc = subprocess.run(
                cmd,
                input=prompt,
                capture_output=True,
                text=True,
                timeout=self.timeout + 20,
                cwd=os.path.expanduser("~"),
            )

        except FileNotFoundError as exc:
            raise RuntimeError(
                "chatgpt-tab not found. Run the ChatGPT bridge setup first."
            ) from exc

        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(
                f"ChatGPT browser turn timed out after {self.timeout}s"
            ) from exc

        if proc.returncode != 0:
            raise RuntimeError(
                "chatgpt-tab failed "
                f"({proc.returncode}): "
                f"{(proc.stderr or proc.stdout)[:600]}"
            )

        return proc.stdout.strip()

    @staticmethod
    def _flatten(messages: List[BaseMessage]) -> str:
        parts = []

        for m in messages:
            role = getattr(m, "type", "human")
            content = m.content

            if isinstance(content, list):
                # Browser adapter is text-only for now.
                content = " ".join(
                    b.get("text", "")
                    for b in content
                    if isinstance(b, dict)
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

        text = self._call_web(
            self._flatten(messages)
        )

        return ChatResult(
            generations=[
                ChatGeneration(
                    message=AIMessage(content=text)
                )
            ]
        )

    def with_structured_output(
        self,
        schema: Type[BaseModel],
        *,
        include_raw: bool = False,
        **kwargs: Any,
    ) -> Runnable:

        model = self

        def invoke(messages: Any) -> Any:
            if hasattr(messages, "to_messages"):
                messages = messages.to_messages()
            elif isinstance(messages, str):
                from langchain_core.messages import HumanMessage
                messages = [HumanMessage(content=messages)]
            elif isinstance(messages, BaseMessage):
                messages = [messages]

            prompt = model._flatten(
                list(messages)
            )

            prompt += (
                "\n\n[OUTPUT CONTRACT]\n"
                "Return ONE valid JSON object matching the schema below. "
                "Do not use a markdown fence. "
                "You may not omit required fields.\n\n"
                + json.dumps(schema.model_json_schema())
            )

            for attempt in range(model.repair_attempts + 1):
                text = model._call_web(prompt)
                raw = AIMessage(content=text)
                try:
                    parsed = validate_response(text, schema)
                except ValueError as exc:
                    if attempt < model.repair_attempts:
                        prompt = (
                            "Correct the previous response. Return only ONE valid JSON object "
                            "matching this schema, with all required fields. No prose or fences.\n"
                            + json.dumps(schema.model_json_schema())
                            + "\nValidation error:\n" + str(exc)[:4000]
                            + "\nPrevious response:\n" + text
                        )
                        continue
                    if include_raw:
                        return {"raw": raw, "parsed": None, "parsing_error": exc}
                    raise
                if include_raw:
                    return {"raw": raw, "parsed": parsed, "parsing_error": None}
                return parsed

        return RunnableLambda(invoke)
