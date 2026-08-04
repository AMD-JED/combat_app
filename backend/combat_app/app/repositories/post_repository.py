from typing import Optional, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, func
from sqlalchemy.orm import selectinload

from app.models.post import Post, Comment, post_likes
from app.repositories.base_repository import BaseRepository


class PostRepository(BaseRepository[Post]):

    def __init__(self, db: AsyncSession):
        super().__init__(Post, db)

    async def get_feed(self, following_ids: List[int], skip: int = 0, limit: int = 20) -> List[Post]:
        """Get posts from users that the current user follows."""
        result = await self.db.execute(
            select(Post)
            .options(
                selectinload(Post.author),
                selectinload(Post.liked_by),
                selectinload(Post.comments)   # ⬅️ ضروري جداً - رجّعه
            )
        .where(Post.author_id.in_(following_ids))
        .order_by(Post.created_at.desc())
        .offset(skip)
        .limit(limit)
        )
        return list(result.scalars().all())

    async def get_user_posts(self, user_id: int, skip: int = 0, limit: int = 20) -> List[Post]:
        result = await self.db.execute(
            select(Post)
            .options(
                selectinload(Post.author),
                selectinload(Post.comments),
                selectinload(Post.liked_by)
            )
            .where(Post.author_id == user_id)
            .order_by(Post.created_at.desc())
            .offset(skip)
            .limit(limit)
    )
        return list(result.scalars().all())

    async def like_post(self, user_id: int, post_id: int) -> bool:
        existing = await self.db.execute(
            select(post_likes).where(
                and_(post_likes.c.user_id == user_id, post_likes.c.post_id == post_id)
            )
        )
        if existing.first():
            # Unlike
            await self.db.execute(
                post_likes.delete().where(
                    and_(post_likes.c.user_id == user_id, post_likes.c.post_id == post_id)
                )
            )
            return False
        # Like
        await self.db.execute(post_likes.insert().values(user_id=user_id, post_id=post_id))
        return True

    async def add_comment(self, post_id: int, author_id: int, content: str) -> Comment:
        comment = Comment(post_id=post_id, author_id=author_id, content=content)
        self.db.add(comment)
        await self.db.flush()
        await self.db.refresh(comment)
        return comment


class ExerciseRepository(BaseRepository):

    def __init__(self, db: AsyncSession):
        from app.models.exercise import Exercise
        super().__init__(Exercise, db)

    async def filter_exercises(self, category=None, difficulty=None, sport_type=None, search=None, skip=0, limit=20):
        from app.models.exercise import Exercise
        query = select(Exercise)
        if category:
            query = query.where(Exercise.category == category)
        if difficulty:
            query = query.where(Exercise.difficulty == difficulty)
        if sport_type:
            query = query.where(Exercise.sport_types.ilike(f"%{sport_type}%"))
        if search:
            query = query.where(
                Exercise.name.ilike(f"%{search}%") | Exercise.description.ilike(f"%{search}%")
            )
        result = await self.db.execute(query.offset(skip).limit(limit))
        return list(result.scalars().all())
