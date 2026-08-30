import enum
from datetime import datetime, time
from typing import Optional

from pydantic import BaseModel, Field, model_validator

from app.schemas.user import UserPublicResponse


class RecurrenceDay(str, enum.Enum):
    MONDAY = "monday"
    TUESDAY = "tuesday"
    WEDNESDAY = "wednesday"
    THURSDAY = "thursday"
    FRIDAY = "friday"
    SATURDAY = "saturday"
    SUNDAY = "sunday"


# ──────────────────────────────────────────────
#  Requests
# ──────────────────────────────────────────────

class OpenMatCreate(BaseModel):
    title: str = Field(..., min_length=2, max_length=150)
    description: Optional[str] = Field(None, max_length=2000)
    is_recurring: bool = False

    # One-time events:
    event_datetime: Optional[datetime] = None

    # Recurring (weekly) events:
    recurrence_day: Optional[RecurrenceDay] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None

    location_override: Optional[str] = Field(None, max_length=200)

    @model_validator(mode="after")
    def validate_schedule_shape(self):
        if self.is_recurring:
            if not self.recurrence_day or not self.start_time:
                raise ValueError("Recurring open mats require recurrence_day and start_time")
            if self.event_datetime is not None:
                raise ValueError("Recurring open mats should not set event_datetime")
        else:
            if not self.event_datetime:
                raise ValueError("One-time open mats require event_datetime")
            if self.recurrence_day or self.start_time or self.end_time:
                raise ValueError("One-time open mats should not set recurrence_day/start_time/end_time")
        return self


# ──────────────────────────────────────────────
#  Responses
# ──────────────────────────────────────────────

class OpenMatResponse(BaseModel):
    """Full detail view — gym_name/location/rsvp_count/is_rsvped_by_me
    are computed at the endpoint layer (not plain ORM attributes), so
    this is always built explicitly rather than via from_attributes."""
    id: int
    gym_id: int
    gym_name: str
    title: str
    description: Optional[str] = None
    is_recurring: bool
    event_datetime: Optional[datetime] = None
    recurrence_day: Optional[RecurrenceDay] = None
    start_time: Optional[time] = None
    end_time: Optional[time] = None
    location: Optional[str] = None  # resolved: location_override or gym.location
    rsvp_count: int
    is_rsvped_by_me: bool
    created_at: datetime


class OpenMatBrief(BaseModel):
    """Lightweight card for search results — no gym join, no RSVP count."""
    id: int
    title: str
    gym_id: int
    is_recurring: bool
    event_datetime: Optional[datetime] = None
    recurrence_day: Optional[RecurrenceDay] = None

    model_config = {"from_attributes": True}


class OpenMatRSVPResponse(BaseModel):
    user: UserPublicResponse
    created_at: datetime

    model_config = {"from_attributes": True}
