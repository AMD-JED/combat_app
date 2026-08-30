from typing import List, Optional

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.gym import Gym, GymMembership
from app.repositories.base_repository import BaseRepository


class GymRepository(BaseRepository[Gym]):
    def __init__(self, db: AsyncSession):
        super().__init__(Gym, db)

    async def get_with_owner(self, gym_id: int) -> Optional[Gym]:
        result = await self.db.execute(
            select(Gym).options(selectinload(Gym.owner)).where(Gym.id == gym_id)
        )
        return result.scalar_one_or_none()

    async def list_active(self, skip: int = 0, limit: int = 20) -> List[Gym]:
        result = await self.db.execute(
            select(Gym)
            .options(selectinload(Gym.owner))
            .where(Gym.is_active.is_(True))
            .order_by(Gym.created_at.desc())
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())

    async def search(self, query: str, skip: int = 0, limit: int = 20) -> List[Gym]:
        result = await self.db.execute(
            select(Gym)
            .where(
                Gym.is_active.is_(True),
                or_(Gym.name.ilike(f"%{query}%"), Gym.location.ilike(f"%{query}%")),
            )
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())

    async def count_members(self, gym_id: int) -> int:
        result = await self.db.execute(
            select(func.count()).select_from(GymMembership).where(GymMembership.gym_id == gym_id)
        )
        return result.scalar_one()

    async def create_with_owner(self, owner_id: int, data: dict) -> Gym:
        gym = Gym(owner_id=owner_id, **data)
        gym = await self.create(gym)
        # The owner is also a full membership row (role='owner'), so
        # member listings are complete without special-casing the owner.
        await self.db.execute(
            GymMembership.__table__.insert().values(gym_id=gym.id, user_id=owner_id, role="owner")
        )
        await self.db.flush()
        return gym

    async def get_membership(self, gym_id: int, user_id: int) -> Optional[GymMembership]:
        result = await self.db.execute(
            select(GymMembership).where(
                and_(GymMembership.gym_id == gym_id, GymMembership.user_id == user_id)
            )
        )
        return result.scalar_one_or_none()

    async def join(self, gym_id: int, user_id: int) -> Optional[GymMembership]:
        """Returns the new membership, or None if already a member."""
        existing = await self.get_membership(gym_id, user_id)
        if existing:
            return None
        membership = GymMembership(gym_id=gym_id, user_id=user_id, role="member")
        self.db.add(membership)
        await self.db.flush()
        await self.db.refresh(membership)
        return membership

    async def leave(self, gym_id: int, user_id: int) -> bool:
        """Returns False if not a member, or if trying to remove the owner
        (owner must transfer ownership first — out of scope for v7)."""
        membership = await self.get_membership(gym_id, user_id)
        if not membership:
            return False
        if membership.role == "owner":
            return False
        await self.db.delete(membership)
        await self.db.flush()
        return True

    async def list_members(self, gym_id: int) -> List[GymMembership]:
        result = await self.db.execute(
            select(GymMembership)
            .options(selectinload(GymMembership.user))
            .where(GymMembership.gym_id == gym_id)
            .order_by(GymMembership.role.desc(), GymMembership.joined_at.asc())
        )
        return list(result.scalars().all())
