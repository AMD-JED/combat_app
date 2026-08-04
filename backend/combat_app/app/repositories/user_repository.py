from typing import Optional, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from sqlalchemy.orm import selectinload

from app.models.user import User, follows
from app.repositories.base_repository import BaseRepository


class UserRepository(BaseRepository[User]):

    def __init__(self, db: AsyncSession):
        super().__init__(User, db)

    async def get_by_email(self, email: str) -> Optional[User]:
        result = await self.db.execute(select(User).where(User.email == email))
        return result.scalar_one_or_none()

    async def get_by_username(self, username: str) -> Optional[User]:
        result = await self.db.execute(select(User).where(User.username == username))
        return result.scalar_one_or_none()

    async def get_by_google_id(self, google_id: str) -> Optional[User]:
        result = await self.db.execute(select(User).where(User.google_id == google_id))
        return result.scalar_one_or_none()

    async def get_with_relations(self, user_id: int) -> Optional[User]:
        result = await self.db.execute(
            select(User)
            .options(selectinload(User.followers), selectinload(User.following))
            .where(User.id == user_id)
        )
        return result.scalar_one_or_none()

    async def follow(self, follower_id: int, followed_id: int) -> bool:
        """Returns True if followed, False if already following."""
        existing = await self.db.execute(
            select(follows).where(
                and_(
                    follows.c.follower_id == follower_id,
                    follows.c.followed_id == followed_id,
                )
            )
        )
        if existing.first():
            return False
        await self.db.execute(
            follows.insert().values(follower_id=follower_id, followed_id=followed_id)
        )
        return True

    async def unfollow(self, follower_id: int, followed_id: int) -> bool:
        result = await self.db.execute(
            follows.delete().where(
                and_(
                    follows.c.follower_id == follower_id,
                    follows.c.followed_id == followed_id,
                )
            )
        )
        return result.rowcount > 0

    async def search(self, query: str, skip: int = 0, limit: int = 20) -> List[User]:
        result = await self.db.execute(
            select(User)
            .where(
                User.username.ilike(f"%{query}%") | User.full_name.ilike(f"%{query}%")
            )
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())
