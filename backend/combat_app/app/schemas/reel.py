from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field

from app.schemas.user import UserPublicResponse


class ReelCreate(BaseModel):
    media_url: str = Field(..., max_length=500)
    thumbnail_url: Optional[str] = Field(None, max_length=500)
    caption: Optional[str] = Field(None, max_length=1000)
    sport_id: Optional[int] = None
    duration_seconds: Optional[int] = Field(None, ge=0)


class ReelResponse(BaseModel):
    id: int
    author: UserPublicResponse
    media_url: str
    thumbnail_url: Optional[str] = None
    caption: Optional[str] = None
    sport_id: Optional[int] = None
    duration_seconds: Optional[int] = None
    view_count: int = 0
    likes_count: int = 0
    comments_count: int = 0
    is_liked_by_me: bool = False
    # Surfaced from author.is_coach at serialization time (v9 decision:
    # anyone can post Reels, coaches just get a badge) — not a DB column.
    is_coach_content: bool = False
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
