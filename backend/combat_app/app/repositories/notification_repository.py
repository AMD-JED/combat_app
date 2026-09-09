from datetime import datetime
from typing import List, Optional

from sqlalchemy import select, update, and_, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.notification import Notification, DeviceToken, SessionReminder
from app.repositories.base_repository import BaseRepository


class NotificationRepository(BaseRepository[Notification]):

    def __init__(self, db: AsyncSession):
        super().__init__(Notification, db)

    async def create_notification(
        self,
        recipient_id: int,
        type: str,
        title: str,
        body: str,
        actor_id: Optional[int] = None,
        data: Optional[dict] = None,
    ) -> Notification:
        notif = Notification(
            recipient_id=recipient_id,
            actor_id=actor_id,
            type=type,
            title=title,
            body=body,
            data=data or {},
        )
        self.db.add(notif)
        await self.db.flush()
        await self.db.refresh(notif)
        return notif

    async def get_for_user(self, user_id: int, skip: int = 0, limit: int = 50) -> List[Notification]:
        result = await self.db.execute(
            select(Notification)
            .options(selectinload(Notification.actor))
            .where(Notification.recipient_id == user_id)
            .order_by(Notification.created_at.desc())
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())

    async def get_unread_count(self, user_id: int) -> int:
        result = await self.db.execute(
            select(func.count())
            .select_from(Notification)
            .where(Notification.recipient_id == user_id, Notification.is_read.is_(False))
        )
        return result.scalar_one()

    async def mark_read(self, notification_id: int, user_id: int) -> bool:
        result = await self.db.execute(
            update(Notification)
            .where(Notification.id == notification_id, Notification.recipient_id == user_id)
            .values(is_read=True)
        )
        return result.rowcount > 0

    async def mark_all_read(self, user_id: int) -> int:
        result = await self.db.execute(
            update(Notification)
            .where(Notification.recipient_id == user_id, Notification.is_read.is_(False))
            .values(is_read=True)
        )
        return result.rowcount

    async def delete_for_user(self, notification_id: int, user_id: int) -> bool:
        notif = await self.get_by_id(notification_id)
        if not notif or notif.recipient_id != user_id:
            return False
        await self.db.delete(notif)
        return True

    # ── Device Tokens ───────────────────────────────────────────────

    async def register_device_token(self, user_id: int, fcm_token: str, platform: str) -> DeviceToken:
        """A token is globally unique. If it was previously registered to
        a DIFFERENT user (device changed hands via logout/login), it is
        re-parented to the current user rather than causing a duplicate
        key error or leaving the old owner subscribed to someone else's
        device. See DeviceToken docstring in app/models/notification.py."""
        result = await self.db.execute(select(DeviceToken).where(DeviceToken.fcm_token == fcm_token))
        existing = result.scalar_one_or_none()
        if existing:
            existing.user_id = user_id
            existing.platform = platform
            await self.db.flush()
            return existing

        token = DeviceToken(user_id=user_id, fcm_token=fcm_token, platform=platform)
        self.db.add(token)
        await self.db.flush()
        return token

    async def unregister_device_token(self, user_id: int, fcm_token: str) -> bool:
        result = await self.db.execute(
            select(DeviceToken).where(
                DeviceToken.fcm_token == fcm_token, DeviceToken.user_id == user_id
            )
        )
        token = result.scalar_one_or_none()
        if not token:
            return False
        await self.db.delete(token)
        return True

    async def get_tokens_for_user(self, user_id: int) -> List[str]:
        result = await self.db.execute(
            select(DeviceToken.fcm_token).where(DeviceToken.user_id == user_id)
        )
        return [row[0] for row in result.all()]


class SessionReminderRepository(BaseRepository[SessionReminder]):

    def __init__(self, db: AsyncSession):
        super().__init__(SessionReminder, db)

    async def create_reminder(
        self, user_id: int, session_id: int, lead_time: str, remind_at: datetime
    ) -> SessionReminder:
        reminder = SessionReminder(
            user_id=user_id, session_id=session_id, lead_time=lead_time, remind_at=remind_at
        )
        self.db.add(reminder)
        await self.db.flush()
        await self.db.refresh(reminder)
        return reminder

    async def get_for_user(self, user_id: int) -> List[SessionReminder]:
        result = await self.db.execute(
            select(SessionReminder)
            .where(SessionReminder.user_id == user_id)
            .order_by(SessionReminder.remind_at.asc())
        )
        return list(result.scalars().all())

    async def get_due(self, now: datetime, limit: int = 100) -> List[SessionReminder]:
        """Used by the scheduler tick (see app/services/reminder_scheduler.py).
        Loads `user` and `session` eagerly since the scheduler runs
        outside a request context and has no other chance to fetch them."""
        result = await self.db.execute(
            select(SessionReminder)
            .options(selectinload(SessionReminder.user), selectinload(SessionReminder.session))
            .where(SessionReminder.sent.is_(False), SessionReminder.remind_at <= now)
            .order_by(SessionReminder.remind_at.asc())
            .limit(limit)
        )
        return list(result.scalars().all())

    async def mark_sent(self, reminder_id: int) -> None:
        await self.db.execute(
            update(SessionReminder).where(SessionReminder.id == reminder_id).values(sent=True)
        )
