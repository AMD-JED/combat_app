from typing import List, Optional

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.open_mat import OpenMat, OpenMatRSVP
from app.repositories.base_repository import BaseRepository


class OpenMatRepository(BaseRepository[OpenMat]):
    def __init__(self, db: AsyncSession):
        super().__init__(OpenMat, db)

    async def get_with_gym(self, open_mat_id: int) -> Optional[OpenMat]:
        result = await self.db.execute(
            select(OpenMat).options(selectinload(OpenMat.gym)).where(OpenMat.id == open_mat_id)
        )
        return result.scalar_one_or_none()

    async def list_for_gym(self, gym_id: int) -> List[OpenMat]:
        result = await self.db.execute(
            select(OpenMat)
            .options(selectinload(OpenMat.gym))
            .where(OpenMat.gym_id == gym_id)
            .order_by(OpenMat.created_at.desc())
        )
        return list(result.scalars().all())

    async def search(self, query: str, skip: int = 0, limit: int = 20) -> List[OpenMat]:
        result = await self.db.execute(
            select(OpenMat)
            .where(or_(OpenMat.title.ilike(f"%{query}%"), OpenMat.description.ilike(f"%{query}%")))
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())

    async def count_rsvps(self, open_mat_id: int) -> int:
        result = await self.db.execute(
            select(func.count()).select_from(OpenMatRSVP).where(OpenMatRSVP.open_mat_id == open_mat_id)
        )
        return result.scalar_one()

    async def get_rsvp(self, open_mat_id: int, user_id: int) -> Optional[OpenMatRSVP]:
        result = await self.db.execute(
            select(OpenMatRSVP).where(
                and_(OpenMatRSVP.open_mat_id == open_mat_id, OpenMatRSVP.user_id == user_id)
            )
        )
        return result.scalar_one_or_none()

    async def rsvp(self, open_mat_id: int, user_id: int) -> Optional[OpenMatRSVP]:
        """Returns the new RSVP, or None if already RSVP'd."""
        existing = await self.get_rsvp(open_mat_id, user_id)
        if existing:
            return None
        entry = OpenMatRSVP(open_mat_id=open_mat_id, user_id=user_id)
        self.db.add(entry)
        await self.db.flush()
        await self.db.refresh(entry)
        return entry

    async def cancel_rsvp(self, open_mat_id: int, user_id: int) -> bool:
        existing = await self.get_rsvp(open_mat_id, user_id)
        if not existing:
            return False
        await self.db.delete(existing)
        await self.db.flush()
        return True

    async def list_rsvps(self, open_mat_id: int) -> List[OpenMatRSVP]:
        result = await self.db.execute(
            select(OpenMatRSVP)
            .options(selectinload(OpenMatRSVP.user))
            .where(OpenMatRSVP.open_mat_id == open_mat_id)
            .order_by(OpenMatRSVP.created_at.asc())
        )
        return list(result.scalars().all())
