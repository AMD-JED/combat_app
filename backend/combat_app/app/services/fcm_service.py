"""
v10 — Firebase Cloud Messaging (push) service.

Same isolation pattern as app/services/gemini_service.py: this is the
ONE file that knows about Firebase. Every caller (notification_service,
reminder_scheduler) only calls `send_push(...)` below and has no idea
FCM is the provider — swapping to another push provider later means
rewriting this file only.

`firebase-admin`'s messaging client is synchronous (blocking network
I/O), so calls are wrapped in `asyncio.to_thread`, same reasoning as
Gemini: a slow FCM call must not stall the event loop for every other
concurrent request.

Configuration: `FIREBASE_CREDENTIALS_JSON` in .env holds the *contents*
of a Firebase service-account JSON key (not a file path) — this avoids
needing a separate secret file to manage/gitignore on top of .env,
consistent with this project's existing "everything sensitive lives in
.env" convention. Empty by default so the app still boots without it —
callers get a clear RuntimeError instead of a crash at import time,
mirroring GEMINI_API_KEY's empty-default pattern in config.py.
"""
import asyncio
import json
from typing import Any, Dict, List

import firebase_admin
from firebase_admin import credentials, messaging

from app.core.config import settings

_initialized = False


def _ensure_initialized() -> None:
    global _initialized
    if _initialized:
        return
    if not settings.FIREBASE_CREDENTIALS_JSON:
        raise RuntimeError(
            "FIREBASE_CREDENTIALS_JSON is not set. Add the contents of your "
            "Firebase service-account key JSON to your .env file — see "
            "Firebase Console > Project Settings > Service Accounts."
        )
    try:
        cred_dict = json.loads(settings.FIREBASE_CREDENTIALS_JSON)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"FIREBASE_CREDENTIALS_JSON is not valid JSON: {e}")

    cred = credentials.Certificate(cred_dict)
    firebase_admin.initialize_app(cred)
    _initialized = True


def _send_multicast_sync(tokens: List[str], title: str, body: str, data: Dict[str, Any]) -> List[str]:
    """Runs in a worker thread (see send_push). Returns the list of
    tokens that FCM reports as invalid/unregistered, so the caller can
    clean them out of device_tokens (a device that uninstalled the app
    or had its token rotated stays there forever otherwise)."""
    _ensure_initialized()

    # FCM data payloads must be flat string->string maps.
    string_data = {k: str(v) for k, v in data.items()}

    message = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        data=string_data,
        tokens=tokens,
    )
    response = messaging.send_each_for_multicast(message)

    invalid_tokens = []
    for token, result in zip(tokens, response.responses):
        if not result.success:
            code = getattr(result.exception, "code", "")
            if code in ("NOT_FOUND", "UNREGISTERED", "INVALID_ARGUMENT"):
                invalid_tokens.append(token)
    return invalid_tokens


async def send_push(tokens: List[str], title: str, body: str, data: Dict[str, Any]) -> List[str]:
    """
    Sends one push to all of a user's registered devices at once (FCM's
    multicast supports up to 500 tokens per call, far more than any
    single user will realistically have registered).

    Returns the subset of `tokens` that FCM reports as dead so the
    caller (notification_service) can prune them from device_tokens.
    Never raises for individual per-token delivery failures — only for
    total misconfiguration (missing/invalid credentials), which the
    caller is expected to catch and log rather than let bubble up and
    fail the underlying action (a like/comment/message must succeed
    even if the push notification for it fails).
    """
    if not tokens:
        return []
    return await asyncio.to_thread(_send_multicast_sync, tokens, title, body, data)
