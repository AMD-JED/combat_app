"""
v8 — AI provider service (Gemini today).

This is the ONE file that knows about a specific AI provider. Every
other part of AI Coach (models, repository, context builder, endpoint)
only calls `generate_coach_reply(...)` below and has no idea it's
Gemini under the hood. Swapping to Claude, OpenAI, or a local Ollama
model later means rewriting this file only.

`google-generativeai`'s client is synchronous (blocking network I/O), so
calls are wrapped in `asyncio.to_thread` to avoid blocking the FastAPI
event loop — otherwise a slow Gemini response would stall every other
concurrent request being handled by this worker.
"""
import asyncio
from typing import List

import google.generativeai as genai

from app.core.config import settings

_configured = False


def _ensure_configured() -> None:
    global _configured
    if not _configured:
        if not settings.GEMINI_API_KEY:
            raise RuntimeError(
                "GEMINI_API_KEY is not set. Add it to your .env file — "
                "see README for how to get one from Google AI Studio."
            )
        genai.configure(api_key=settings.GEMINI_API_KEY)
        _configured = True


def _history_to_gemini_format(history: List[dict]) -> list:
    """`history` is a list of {"role": "user"|"assistant", "content": str}
    in chronological order. Gemini's chat history format uses "model"
    instead of "assistant" for the AI's turns."""
    formatted = []
    for msg in history:
        role = "model" if msg["role"] == "assistant" else "user"
        formatted.append({"role": role, "parts": [msg["content"]]})
    return formatted


def _generate_sync(system_context: str, history: List[dict], user_message: str) -> str:
    _ensure_configured()
    model = genai.GenerativeModel(
        model_name=settings.GEMINI_MODEL,
        system_instruction=system_context,
    )
    chat = model.start_chat(history=_history_to_gemini_format(history))
    response = chat.send_message(user_message)
    return response.text


async def generate_coach_reply(
    system_context: str,
    history: List[dict],
    user_message: str,
) -> str:
    """
    system_context: output of coach_context_service.build_user_context()
    history: prior messages in this conversation (chronological order),
             NOT including `user_message` itself
    user_message: the new message just sent by the athlete
    """
    return await asyncio.to_thread(_generate_sync, system_context, history, user_message)
