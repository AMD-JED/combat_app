from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel

from app.schemas.gym import GymBrief
from app.schemas.open_mat import OpenMatBrief
from app.schemas.user import UserPublicResponse


class PostBrief(BaseModel):
    """Lightweight post card for search results — no author join, so
    every category in /search stays a single cheap query."""
    id: int
    content: Optional[str] = None
    author_id: int
    created_at: datetime

    model_config = {"from_attributes": True}


class ReelBrief(BaseModel):
    """v9 — lightweight reel card for search results."""
    id: int
    caption: Optional[str] = None
    author_id: int
    sport_id: Optional[int] = None
    created_at: datetime

    model_config = {"from_attributes": True}


class StoryBrief(BaseModel):
    """v9 — lightweight story card for search results. Only active,
    public, text-type stories are ever returned here (see
    SearchRepository.search_stories)."""
    id: int
    text_content: Optional[str] = None
    author_id: int
    expires_at: datetime

    model_config = {"from_attributes": True}


class SearchResults(BaseModel):
    """
    Unified search across athletes, gyms, open mats, posts, reels, and
    active stories. Every category is capped independently by `limit`
    (see GET /search) — this is plain ILIKE matching per category, not a
    ranked/relevance search engine. Good enough for an MVP directory; a
    real full-text search (Postgres tsvector, or an external engine) is a
    future upgrade if search quality becomes a problem at scale.
    """
    users: List[UserPublicResponse]
    gyms: List[GymBrief]
    open_mats: List[OpenMatBrief]
    posts: List[PostBrief]
    reels: List[ReelBrief] = []
    stories: List[StoryBrief] = []
