from typing import List, Optional

from sqlalchemy import select, and_, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.post import Comment
from app.models.reel import Reel, ReelLike
from app.repositories.base_repository import BaseRepository


class ReelRepository(BaseRepository[Reel]):

    def __init__(self, db: AsyncSession):
        super().__init__(Reel, db)

    async def get_feed(
        self, sport_id: Optional[int] = None, skip: int = 0, limit: int = 20
    ) -> List[Reel]:
        """v9 decision: Reels feed is filtered by sport_id, not a
        following-based chronological feed like Post.feed."""
        query = (
            select(Reel)
            .options(selectinload(Reel.author), selectinload(Reel.likes), selectinload(Reel.comments))
            .order_by(Reel.created_at.desc())
        )
        if sport_id is not None:
            query = query.where(Reel.sport_id == sport_id)
        query = query.offset(skip).limit(limit)

        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def get_with_relations(self, reel_id: int) -> Optional[Reel]:
        result = await self.db.execute(
            select(Reel)
            .options(selectinload(Reel.author), selectinload(Reel.likes), selectinload(Reel.comments))
            .where(Reel.id == reel_id)
        )
        return result.scalar_one_or_none()

    async def increment_view(self, reel_id: int) -> None:
        await self.db.execute(
            update(Reel).where(Reel.id == reel_id).values(view_count=Reel.view_count + 1)
        )

    async def toggle_like(self, reel_id: int, user_id: int) -> str:
        """Simple like/unlike (NOT the 6-way PostReaction system —
        confirmed v9 decision). Returns 'liked' or 'unliked'."""
        result = await self.db.execute(
            select(ReelLike).where(and_(ReelLike.reel_id == reel_id, ReelLike.user_id == user_id))
        )
        existing = result.scalar_one_or_none()
        if existing:
            await self.db.delete(existing)
            return "unliked"
        self.db.add(ReelLike(reel_id=reel_id, user_id=user_id))
        return "liked"

    async def is_liked_by(self, reel_id: int, user_id: int) -> bool:
        result = await self.db.execute(
            select(ReelLike.id).where(and_(ReelLike.reel_id == reel_id, ReelLike.user_id == user_id))
        )
        return result.scalar_one_or_none() is not None

    async def add_comment(self, reel_id: int, author_id: int, content: str) -> Comment:
        comment = Comment(reel_id=reel_id, author_id=author_id, content=content)
        self.db.add(comment)
        await self.db.flush()
        await self.db.refresh(comment)
        return comment

    async def delete_reel(self, reel_id: int) -> bool:
        """Explicit ORM-level delete (loads `likes`/`comments` first) so
        child rows are cleaned up via cascade regardless of SQLite FK
        pragma support — same reasoning as StoryRepository.delete_story."""
        result = await self.db.execute(
            select(Reel)
            .options(selectinload(Reel.likes), selectinload(Reel.comments))
            .where(Reel.id == reel_id)
        )
        reel = result.scalar_one_or_none()
        if not reel:
            return False
        await self.db.delete(reel)
        await self.db.flush()
        return True

    async def get_comments(self, reel_id: int, skip: int = 0, limit: int = 50) -> List[Comment]:
        result = await self.db.execute(
            select(Comment)
            .options(selectinload(Comment.author))
            .where(Comment.reel_id == reel_id)
            .order_by(Comment.created_at.asc())
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())
