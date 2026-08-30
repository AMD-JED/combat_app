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


class SearchResults(BaseModel):
    """
    Unified search across athletes, gyms, open mats, and posts.
    Every category is capped independently by `limit` (see GET /search) —
    this is plain ILIKE matching per category, not a ranked/relevance
    search engine. Good enough for an MVP directory; a real full-text
    search (Postgres tsvector, or an external engine) is a future
    upgrade if search quality becomes a problem at scale.
    """
    users: List[UserPublicResponse]
    gyms: List[GymBrief]
    open_mats: List[OpenMatBrief]
    posts: List[PostBrief]
