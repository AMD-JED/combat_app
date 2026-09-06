"""
v7 — Unified search.

Not tied to a single model, so this doesn't extend BaseRepository like
the other repositories — it's a thin wrapper around one ILIKE query per
table. See app/schemas/search.py:SearchResults for why each category
returns a "brief" shape (no joins, to keep this a handful of cheap
queries rather than N+1 per category).
"""
from datetime import datetime, timezone
from typing import List

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.gym import Gym
from app.models.open_mat import OpenMat
from app.models.post import Post
from app.models.reel import Reel
from app.models.story import Story
from app.models.user import User


class SearchRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def search_users(self, query: str, limit: int = 5) -> List[User]:
        result = await self.db.execute(
            select(User)
            .where(or_(User.username.ilike(f"%{query}%"), User.full_name.ilike(f"%{query}%")))
            .limit(limit)
        )
        return list(result.scalars().all())

    async def search_gyms(self, query: str, limit: int = 5) -> List[Gym]:
        result = await self.db.execute(
            select(Gym)
            .where(
                Gym.is_active.is_(True),
                or_(Gym.name.ilike(f"%{query}%"), Gym.location.ilike(f"%{query}%")),
            )
            .limit(limit)
        )
        return list(result.scalars().all())

    async def search_open_mats(self, query: str, limit: int = 5) -> List[OpenMat]:
        result = await self.db.execute(
            select(OpenMat)
            .where(or_(OpenMat.title.ilike(f"%{query}%"), OpenMat.description.ilike(f"%{query}%")))
            .limit(limit)
        )
        return list(result.scalars().all())

    async def search_posts(self, query: str, limit: int = 5) -> List[Post]:
        result = await self.db.execute(
            select(Post).where(Post.content.ilike(f"%{query}%")).limit(limit)
        )
        return list(result.scalars().all())

    async def search_reels(self, query: str, limit: int = 5) -> List[Reel]:
        """v9 — Reels have no title, only an optional caption."""
        result = await self.db.execute(
            select(Reel).where(Reel.caption.ilike(f"%{query}%")).limit(limit)
        )
        return list(result.scalars().all())

    async def search_stories(self, query: str, limit: int = 5) -> List[Story]:
        """
        v9 — Only active (not expired) PUBLIC stories are searchable, and
        only text-type stories have any text to match against (image/video
        stories carry no caption in this schema — see app/models/story.py).
        """
        result = await self.db.execute(
            select(Story)
            .where(
                Story.expires_at > datetime.now(timezone.utc),
                Story.visibility == "public",
                Story.content_type == "text",
                Story.text_content.ilike(f"%{query}%"),
            )
            .limit(limit)
        )
        return list(result.scalars().all())
