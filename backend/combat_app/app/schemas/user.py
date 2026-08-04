from pydantic import BaseModel, EmailStr, Field, model_validator
from typing import Optional
from datetime import datetime
from app.models.user import SportType, WeightClass


# ──────────────────────────────────────────────
#  Base
# ──────────────────────────────────────────────

class UserBase(BaseModel):
    email: EmailStr
    username: str = Field(..., min_length=3, max_length=50, pattern=r"^[a-zA-Z0-9_]+$")
    full_name: str = Field(..., min_length=2, max_length=100)


# ──────────────────────────────────────────────
#  Registration
# ──────────────────────────────────────────────

class UserCreate(UserBase):
    password: str = Field(..., min_length=8, max_length=100)
    password_confirm: str

    @model_validator(mode="after")
    def passwords_match(self) -> "UserCreate":
        if self.password != self.password_confirm:
            raise ValueError("Passwords do not match")
        return self


# ──────────────────────────────────────────────
#  Profile Update
# ──────────────────────────────────────────────

class UserUpdate(BaseModel):
    full_name: Optional[str] = Field(None, max_length=100)
    sport_type: Optional[SportType] = None
    weight_class: Optional[WeightClass] = None
    belt_rank: Optional[str] = Field(None, max_length=50)
    gym_affiliation: Optional[str] = Field(None, max_length=100)
    coach_name: Optional[str] = Field(None, max_length=100)
    bio: Optional[str] = Field(None, max_length=500)
    location: Optional[str] = Field(None, max_length=100)
    is_coach: Optional[bool] = None

    # Fight record
    wins: Optional[int] = Field(None, ge=0)
    losses: Optional[int] = Field(None, ge=0)
    draws: Optional[int] = Field(None, ge=0)


# ──────────────────────────────────────────────
#  Responses
# ──────────────────────────────────────────────

class UserPublicResponse(BaseModel):
    id: int
    username: str
    full_name: str
    sport_type: Optional[SportType]
    weight_class: Optional[WeightClass]
    belt_rank: Optional[str]
    gym_affiliation: Optional[str]
    bio: Optional[str]
    avatar_url: Optional[str]
    location: Optional[str]
    wins: int
    losses: int
    draws: int
    is_coach: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class UserPrivateResponse(UserPublicResponse):
    email: EmailStr
    is_active: bool
    is_verified: bool
    google_id: Optional[str]


# ──────────────────────────────────────────────
#  Auth Tokens
# ──────────────────────────────────────────────

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class TokenRefreshRequest(BaseModel):
    refresh_token: str
