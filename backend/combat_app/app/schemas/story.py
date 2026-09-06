import enum
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field, model_validator

from app.schemas.user import UserPublicResponse


class StoryContentType(str, enum.Enum):
    IMAGE = "image"
    VIDEO = "video"
    TEXT = "text"


class StoryVisibility(str, enum.Enum):
    PUBLIC = "public"
    FOLLOWERS = "followers"


class StoryCreate(BaseModel):
    content_type: StoryContentType
    media_url: Optional[str] = Field(None, max_length=500)
    text_content: Optional[str] = Field(None, max_length=200)
    background_color: Optional[str] = Field(None, max_length=20)
    visibility: StoryVisibility = StoryVisibility.PUBLIC

    @model_validator(mode="after")
    def _check_content_matches_type(self):
        if self.content_type in (StoryContentType.IMAGE, StoryContentType.VIDEO):
            if not self.media_url:
                raise ValueError(f"media_url is required for content_type={self.content_type.value}")
        elif self.content_type == StoryContentType.TEXT:
            if not self.text_content:
                raise ValueError("text_content is required for content_type=text")
        return self


class StoryResponse(BaseModel):
    id: int
    author: UserPublicResponse
    content_type: StoryContentType
    media_url: Optional[str] = None
    text_content: Optional[str] = None
    background_color: Optional[str] = None
    visibility: StoryVisibility
    views_count: int = 0
    viewed_by_me: bool = False
    created_at: datetime
    expires_at: datetime

    model_config = {"from_attributes": True}


class StoryViewerResponse(BaseModel):
    viewer: UserPublicResponse
    viewed_at: datetime

    model_config = {"from_attributes": True}


class StoryReplyCreate(BaseModel):
    """POST /stories/{id}/reply body — sends a DM to the story's author,
    tagged with `reply_to_story_id` (see app/models/message.py)."""
    content: str = Field(..., min_length=1, max_length=1000)


# ──────────────────────────────────────────────
#  Highlights
# ──────────────────────────────────────────────

class HighlightCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=50)
    story_ids: Optional[List[int]] = None  # optional initial stories to pin


class HighlightAddStories(BaseModel):
    story_ids: List[int] = Field(..., min_length=1)


class HighlightResponse(BaseModel):
    id: int
    title: str
    cover_media_url: Optional[str] = None
    stories: List[StoryResponse] = []
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
