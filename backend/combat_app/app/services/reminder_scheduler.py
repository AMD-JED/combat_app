"""
v10 — Per-minute reminder scheduler.

Runs INSIDE the same FastAPI process via APScheduler's AsyncIOScheduler
(started/stopped from app/main.py's lifespan) — deliberately not Celery
+ a separate broker/worker, since this project has no such queue
infrastructure and a single-process periodic tick is enough at this
scale (see PROJECT_STATUS.md key learnings: prefer the simplest thing
that works over premature infra).

Each tick:
  1. Opens its own DB session (this runs outside any request, so there's
     no FastAPI `Depends(get_db)` to piggyback on — see AsyncSessionLocal
     in app/core/database.py).
  2. Finds every SessionReminder that is due (`remind_at <= now`) and
     not yet sent.
  3. Pushes one notification per due reminder, marks it `sent`, commits.

A crashed/skipped tick just means the reminder fires on the NEXT tick
(up to ~60s late) rather than being lost — `sent` is only set after a
successful commit, so a mid-tick crash leaves the reminder pending and
safe to retry.
"""
import logging
from datetime import datetime, timezone

from apscheduler.schedulers.asyncio import AsyncIOScheduler

from app.core.database import AsyncSessionLocal
from app.repositories.notification_repository import SessionReminderRepository
from app.services import notification_service

logger = logging.getLogger(__name__)

_scheduler = AsyncIOScheduler()


async def _tick() -> None:
    async with AsyncSessionLocal() as db:
        try:
            repo = SessionReminderRepository(db)
            due = await repo.get_due(datetime.now(timezone.utc))

            for reminder in due:
                session = reminder.session
                title = "Training session reminder"
                body = (
                    f"Your {session.session_type} session starts soon"
                    if session else "Your training session starts soon"
                )
                await notification_service.create_and_push(
                    db,
                    recipient_id=reminder.user_id,
                    type="session_reminder",
                    title=title,
                    body=body,
                    data={"session_id": reminder.session_id, "reminder_id": reminder.id},
                )
                await repo.mark_sent(reminder.id)

            await db.commit()
        except Exception:
            await db.rollback()
            logger.exception("Reminder scheduler tick failed")


def start() -> None:
    if not _scheduler.running:
        _scheduler.add_job(_tick, "interval", seconds=60, id="session_reminder_tick", replace_existing=True)
        _scheduler.start()
        logger.info("Session reminder scheduler started (60s tick)")


def shutdown() -> None:
    if _scheduler.running:
        _scheduler.shutdown(wait=False)
        logger.info("Session reminder scheduler stopped")
