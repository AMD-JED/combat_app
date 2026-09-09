import enum
from datetime import datetime
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field

from app.schemas.user import UserPublicResponse


class NotificationType(str, enum.Enum):
    REACTION = "reaction"
    COMMENT = "comment"
    SPARRING_REQUEST = "sparring_request"
    SPARRING_RESPONSE = "sparring_response"
    MESSAGE = "message"
    SESSION_REMINDER = "session_reminder"


class DevicePlatform(str, enum.Enum):
    ANDROID = "android"
    IOS = "ios"
    WEB = "web"


class ReminderLeadTime(str, enum.Enum):
    """Matches the prototype's lead-time labels (SessionReminderModal)."""
    EXACT = "exact"
    FIFTEEN_MIN = "15m"
    THIRTY_MIN = "30m"
    ONE_HOUR = "1h"
    TWO_HOURS = "2h"
    ONE_DAY = "1d"


LEAD_TIME_MINUTES: Dict[str, int] = {
    ReminderLeadTime.EXACT.value: 0,
    ReminderLeadTime.FIFTEEN_MIN.value: 15,
    ReminderLeadTime.THIRTY_MIN.value: 30,
    ReminderLeadTime.ONE_HOUR.value: 60,
    ReminderLeadTime.TWO_HOURS.value: 120,
    ReminderLeadTime.ONE_DAY.value: 24 * 60,
}


# ──────────────────────────────────────────────
#  Device Tokens
# ──────────────────────────────────────────────

class DeviceTokenRegister(BaseModel):
    fcm_token: str = Field(..., max_length=500)
    platform: DevicePlatform = DevicePlatform.ANDROID


class DeviceTokenUnregister(BaseModel):
    fcm_token: str = Field(..., max_length=500)


# ──────────────────────────────────────────────
#  Notifications
# ──────────────────────────────────────────────

class NotificationResponse(BaseModel):
    id: int
    actor: Optional[UserPublicResponse] = None
    type: NotificationType
    title: str
    body: str
    data: Dict[str, Any] = {}
    is_read: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class UnreadCountResponse(BaseModel):
    """Polled as a lightweight fallback on app open/foreground — see
    module docstring in app/models/notification.py for why FCM push is
    the primary channel and this is only a safety net."""
    unread_count: int


# ──────────────────────────────────────────────
#  Session Reminders
# ──────────────────────────────────────────────

class SessionReminderCreate(BaseModel):
    session_id: int
    lead_time: ReminderLeadTime = ReminderLeadTime.THIRTY_MIN


class SessionReminderResponse(BaseModel):
    id: int
    session_id: int
    lead_time: ReminderLeadTime
    remind_at: datetime
    sent: bool
    created_at: datetime

    model_config = {"from_attributes": True}
