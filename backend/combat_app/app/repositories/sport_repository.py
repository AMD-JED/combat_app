from typing import List, Optional

from sqlalchemy import select
from sqlalchemy import update as sa_update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.sport import Sport, UserSportProfile
from app.repositories.base_repository import BaseRepository


class SportRepository(BaseRepository[Sport]):
    def __init__(self, db: AsyncSession):
        super().__init__(Sport, db)

    async def get_by_slug(self, slug: str) -> Optional[Sport]:
        result = await self.db.execute(select(Sport).where(Sport.slug == slug))
        return result.scalar_one_or_none()

    async def get_active_sports(self) -> List[Sport]:
        result = await self.db.execute(select(Sport).where(Sport.is_active.is_(True)))
        return list(result.scalars().all())


class UserSportProfileRepository(BaseRepository[UserSportProfile]):
    def __init__(self, db: AsyncSession):
        super().__init__(UserSportProfile, db)

    async def get_for_user(self, user_id: int) -> List[UserSportProfile]:
        result = await self.db.execute(
            select(UserSportProfile)
            .options(selectinload(UserSportProfile.sport))
            .where(UserSportProfile.user_id == user_id)
        )
        return list(result.scalars().all())

    async def get_by_user_and_sport(
        self, user_id: int, sport_id: int
    ) -> Optional[UserSportProfile]:
        result = await self.db.execute(
            select(UserSportProfile).where(
                UserSportProfile.user_id == user_id,
                UserSportProfile.sport_id == sport_id,
            )
        )
        return result.scalar_one_or_none()

    async def get_with_sport(self, profile_id: int) -> Optional[UserSportProfile]:
        result = await self.db.execute(
            select(UserSportProfile)
            .options(selectinload(UserSportProfile.sport))
            .where(UserSportProfile.id == profile_id)
        )
        return result.scalar_one_or_none()

    async def create_for_user(
        self, user_id: int, sport_id: int, is_primary: bool, attributes: dict
    ) -> UserSportProfile:
        profile = UserSportProfile(
            user_id=user_id,
            sport_id=sport_id,
            is_primary=is_primary,
            attributes=attributes,
        )
        return await self.create(profile)

    async def unset_primary_for_user(self, user_id: int) -> None:
        """يضمن وجود رياضة أساسية واحدة (is_primary=True) فقط لكل مستخدم."""
        await self.db.execute(
            sa_update(UserSportProfile)
            .where(UserSportProfile.user_id == user_id)
            .values(is_primary=False)
        )
