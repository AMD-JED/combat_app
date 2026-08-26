from typing import Optional, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from sqlalchemy.orm import selectinload

from app.models.post import Post, Comment, PostReaction, ReactionType
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
                selectinload(Post.reactions),
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
                selectinload(Post.reactions)
            )
            .where(Post.author_id == user_id)
            .order_by(Post.created_at.desc())
            .offset(skip)
            .limit(limit)
    )
        return list(result.scalars().all())

    async def react_to_post(self, user_id: int, post_id: int, reaction_type: ReactionType) -> str:
        """
        v5 — Add / switch / remove (toggle-off) a user's reaction to a post.
        A user has exactly ONE reaction on a given post at a time:
          - no prior reaction            -> insert, return "added"
          - prior reaction, same type    -> delete it (toggle off), return "removed"
          - prior reaction, other type   -> overwrite type, return "updated"
        Caller (endpoint) is responsible for `await db.commit()`.
        """
        result = await self.db.execute(
            select(PostReaction).where(
                and_(PostReaction.post_id == post_id, PostReaction.user_id == user_id)
            )
        )
        existing = result.scalar_one_or_none()

        if existing is None:
            self.db.add(PostReaction(post_id=post_id, user_id=user_id, reaction_type=reaction_type.value))
            return "added"

        if existing.reaction_type == reaction_type.value:
            await self.db.delete(existing)
            return "removed"

        existing.reaction_type = reaction_type.value
        return "updated"

    async def add_comment(self, post_id: int, author_id: int, content: str) -> Comment:
        comment = Comment(post_id=post_id, author_id=author_id, content=content)
        self.db.add(comment)
        await self.db.flush()
        await self.db.refresh(comment)
        return comment

