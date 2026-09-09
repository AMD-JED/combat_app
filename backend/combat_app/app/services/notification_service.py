"""
v10 — Central notification creation + push entry point.

`create_and_push` is deliberately the ONLY function every hook site
(posts.py, reels.py, sparring.py, message send paths) calls. It:
  1. Always writes the `notifications` row first (source of truth —
     this succeeds even if push fails entirely).
  2. Then best-effort pushes via FCM to every device the recipient has
     registered.

Push failures (missing Firebase config, network error, all-dead tokens)
are caught and logged here — NEVER re-raised — because a failed push
must not roll back or fail the action that triggered it. Liking a post
must succeed whether or not the like's notification push goes through.
This mirrors the AI Coach convention of isolating a flaky external
provider behind one file, except AI Coach's failure IS the point of the
request (so it raises), while a notification's failure is a side
effect of it (so it doesn't).
"""
import logging
from typing import Any, Dict, Optional

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.notification import Notification
from app.repositories.notification_repository import NotificationRepository
from app.services import fcm_service

logger = logging.getLogger(__name__)


async def create_and_push(
    db: AsyncSession,
    recipient_id: int,
    type: str,
    title: str,
    body: str,
    actor_id: Optional[int] = None,
    data: Optional[Dict[str, Any]] = None,
) -> Notification:
    repo = NotificationRepository(db)
    notif = await repo.create_notification(
        recipient_id=recipient_id, type=type, title=title, body=body, actor_id=actor_id, data=data,
    )

    try:
        tokens = await repo.get_tokens_for_user(recipient_id)
        if tokens:
            push_data = {"type": type, "notification_id": notif.id, **(data or {})}
            dead_tokens = await fcm_service.send_push(tokens, title, body, push_data)
            for dead in dead_tokens:
                await repo.unregister_device_token(recipient_id, dead)
    except RuntimeError as e:
        # FIREBASE_CREDENTIALS_JSON missing/invalid — expected in dev
        # environments that haven't set up Firebase yet.
        logger.info("Push skipped (FCM not configured): %s", e)
    except Exception:
        # Any other push failure (network, FCM outage, etc). The
        # notification row already exists and will show up next time
        # the client calls GET /notifications regardless.
        logger.exception("Push notification failed for recipient_id=%s type=%s", recipient_id, type)

    return notif
