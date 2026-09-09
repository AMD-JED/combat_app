"""
v10 — Notifications, Device Tokens, Session Reminders.

Delivery architecture (confirmed v10 decision): Firebase Cloud Messaging
(FCM) is the single delivery channel for BOTH event notifications
(reaction/comment/sparring/message) and session reminders — not a
separate WebSocket broadcast. Rationale: the app already needs FCM for
reminders to work while fully closed (OS-killed WebSockets can't do
that), so reusing it for everything avoids maintaining two delivery
systems. FCM only "wakes up" the client; the `notifications` table
below is always the single source of truth the client re-syncs against
(via GET /notifications), which keeps things correct even if a push is
dropped, delayed, or arrives with a stale device.

`type` is a plain indexed VARCHAR, not a native enum — same convention
as PostReaction.reaction_type / TrainingSession.session_type — so a new
notification type is a Python-only change (see
app/schemas/notification.py:NotificationType).

`data` uses FlexibleJSON (JSONB on Postgres, plain JSON on SQLite) —
same type already defined in app/models/sport.py — to carry whatever
ids a given notification type needs (post_id, reel_id, conversation_id,
sparring_request_id, session_id) without a column per possible target.
"""
from sqlalchemy import (
    Column,
    Integer,
    String,
    Text,
    Boolean,
    DateTime,
    ForeignKey,
    func,
)
from sqlalchemy.orm import relationship

from app.core.database import Base
from app.models.sport import FlexibleJSON


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True, index=True)
    recipient_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # Who caused this notification. Nullable for system-generated ones
    # (session_reminder has no "actor" — it's the user's own schedule).
    actor_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    # reaction | comment | sparring_request | sparring_response | message | session_reminder
    # — see app/schemas/notification.py:NotificationType
    type = Column(String(30), nullable=False, index=True)

    title = Column(String(200), nullable=False)
    body = Column(Text, nullable=False)
    data = Column(FlexibleJSON, nullable=False, default=dict)

    is_read = Column(Boolean, nullable=False, default=False, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    recipient = relationship("User", foreign_keys=[recipient_id])
    actor = relationship("User", foreign_keys=[actor_id])

    def __repr__(self) -> str:
        return f"<Notification recipient={self.recipient_id} type={self.type}>"


class DeviceToken(Base):
    """
    One FCM registration token per physical device. `fcm_token` is
    globally unique (not per-user) because the SAME token can briefly be
    reported by a different user on the same physical device after a
    logout/login swap — registering it re-parents it to the new user and
    removes the stale ownership, rather than allowing duplicate rows
    that would double-send a push to a device that no longer belongs to
    the old account. See NotificationRepository.register_device_token.
    """
    __tablename__ = "device_tokens"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    fcm_token = Column(String(500), nullable=False, unique=True, index=True)
    platform = Column(String(10), nullable=False, default="android")  # android | ios | web

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    user = relationship("User", foreign_keys=[user_id])

    def __repr__(self) -> str:
        return f"<DeviceToken user={self.user_id} platform={self.platform}>"


class SessionReminder(Base):
    """
    A scheduled reminder for a TrainingSession. `remind_at` is
    pre-computed at creation time (session.session_date - lead_time) so
    the scheduler's per-minute query (see
    app/services/reminder_scheduler.py) is a simple indexed range scan —
    it never has to recompute lead-time math for every row on every
    tick. `sent` prevents the same reminder firing twice if the
    scheduler tick overlaps a slow run.
    """
    __tablename__ = "session_reminders"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    session_id = Column(Integer, ForeignKey("training_sessions.id", ondelete="CASCADE"), nullable=False, index=True)

    # exact | 15m | 30m | 1h | 2h | 1d — see app/schemas/notification.py:ReminderLeadTime
    lead_time = Column(String(10), nullable=False)
    remind_at = Column(DateTime(timezone=True), nullable=False, index=True)
    sent = Column(Boolean, nullable=False, default=False, index=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    user = relationship("User", foreign_keys=[user_id])
    session = relationship("TrainingSession", foreign_keys=[session_id])

    def __repr__(self) -> str:
        return f"<SessionReminder user={self.user_id} session={self.session_id} at={self.remind_at}>"
