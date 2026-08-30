import enum
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from app.schemas.user import UserPublicResponse


class SparringStatus(str, enum.Enum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    DECLINED = "declined"
    CANCELLED = "cancelled"
    COMPLETED = "completed"


class SparringRequestAction(str, enum.Enum):
    """Body of POST /sparring/requests/{id}/respond. Who may call which
    action is enforced in the endpoint (see VALID_TRANSITIONS)."""
    ACCEPT = "accept"
    DECLINE = "decline"
    CANCEL = "cancel"
    COMPLETE = "complete"


# ──────────────────────────────────────────────
#  Requests
# ──────────────────────────────────────────────

class SparringRequestCreate(BaseModel):
    recipient_id: int
    message: Optional[str] = Field(None, max_length=500)
    scheduled_at: Optional[datetime] = None
    location: Optional[str] = Field(None, max_length=200)
    gym_id: Optional[int] = None
    open_mat_id: Optional[int] = None


class SparringRequestRespond(BaseModel):
    action: SparringRequestAction


# ──────────────────────────────────────────────
#  Responses
# ──────────────────────────────────────────────

class SparringRequestResponse(BaseModel):
    id: int
    requester: UserPublicResponse
    recipient: UserPublicResponse
    status: SparringStatus
    message: Optional[str] = None
    scheduled_at: Optional[datetime] = None
    location: Optional[str] = None
    gym_id: Optional[int] = None
    open_mat_id: Optional[int] = None
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class SparringMatchSuggestion(BaseModel):
    """One candidate sparring partner, matched on the 'combat' sport
    profile attributes (discipline / weight_class / belt_rank). Never
    corresponds to a row in sparring_requests by itself — it's only a
    recommendation of who to send a manual request to."""
    user: UserPublicResponse
    shared_sport: str
    shared_weight_class: Optional[str] = None
    shared_belt_rank: Optional[str] = None
    match_score: int = Field(..., ge=1, le=3)

    model_config = {"from_attributes": True}
