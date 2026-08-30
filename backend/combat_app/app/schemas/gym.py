import enum
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, EmailStr, Field

from app.schemas.user import UserPublicResponse


class GymRole(str, enum.Enum):
    OWNER = "owner"
    COACH = "coach"
    MEMBER = "member"


# ──────────────────────────────────────────────
#  Requests
# ──────────────────────────────────────────────

class GymCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=150)
    description: Optional[str] = Field(None, max_length=2000)
    location: Optional[str] = Field(None, max_length=200)
    sports: List[str] = Field(default_factory=list, description="Sport.slug values offered, e.g. ['combat']")
    contact_phone: Optional[str] = Field(None, max_length=30)
    contact_email: Optional[EmailStr] = None


class GymUpdate(BaseModel):
    """Partial update — only the owner may call this. All fields optional."""
    name: Optional[str] = Field(None, min_length=2, max_length=150)
    description: Optional[str] = Field(None, max_length=2000)
    location: Optional[str] = Field(None, max_length=200)
    sports: Optional[List[str]] = None
    contact_phone: Optional[str] = Field(None, max_length=30)
    contact_email: Optional[EmailStr] = None
    is_active: Optional[bool] = None


# ──────────────────────────────────────────────
#  Responses
# ──────────────────────────────────────────────

class GymResponse(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    location: Optional[str] = None
    sports: List[str] = []
    contact_phone: Optional[str] = None
    contact_email: Optional[str] = None
    is_active: bool
    owner: Optional[UserPublicResponse] = None
    member_count: int
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class GymBrief(BaseModel):
    """Lightweight gym card — used in search results, where loading the
    owner + counting members for every hit would mean N+1 queries."""
    id: int
    name: str
    location: Optional[str] = None
    sports: List[str] = []

    model_config = {"from_attributes": True}


class GymMemberResponse(BaseModel):
    user: UserPublicResponse
    role: GymRole
    joined_at: datetime

    model_config = {"from_attributes": True}
