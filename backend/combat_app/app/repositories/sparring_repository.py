from datetime import datetime
from typing import List, Optional

from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.sparring import SparringRequest
from app.models.sport import Sport, UserSportProfile
from app.repositories.base_repository import BaseRepository


class SparringRepository(BaseRepository[SparringRequest]):
    def __init__(self, db: AsyncSession):
        super().__init__(SparringRequest, db)

    async def get_with_users(self, request_id: int) -> Optional[SparringRequest]:
        result = await self.db.execute(
            select(SparringRequest)
            .options(
                selectinload(SparringRequest.requester),
                selectinload(SparringRequest.recipient),
            )
            .where(SparringRequest.id == request_id)
        )
        return result.scalar_one_or_none()

    async def get_active_between(self, user_a: int, user_b: int) -> Optional[SparringRequest]:
        """Any currently-active request between these two users, in either
        direction — 'active' means pending (awaiting a response) or
        accepted (an upcoming/ongoing session already agreed on). Used to
        block duplicate/overlapping requests. Declined, cancelled, and
        completed requests are NOT active — a new request is allowed once
        a prior one reaches one of those terminal states."""
        result = await self.db.execute(
            select(SparringRequest).where(
                SparringRequest.status.in_(("pending", "accepted")),
                or_(
                    and_(
                        SparringRequest.requester_id == user_a,
                        SparringRequest.recipient_id == user_b,
                    ),
                    and_(
                        SparringRequest.requester_id == user_b,
                        SparringRequest.recipient_id == user_a,
                    ),
                ),
            )
        )
        return result.scalar_one_or_none()

    async def create_request(
        self,
        requester_id: int,
        recipient_id: int,
        message: Optional[str],
        scheduled_at: Optional[datetime],
        location: Optional[str],
        gym_id: Optional[int] = None,
        open_mat_id: Optional[int] = None,
    ) -> SparringRequest:
        req = SparringRequest(
            requester_id=requester_id,
            recipient_id=recipient_id,
            status="pending",
            message=message,
            scheduled_at=scheduled_at,
            location=location,
            gym_id=gym_id,
            open_mat_id=open_mat_id,
        )
        return await self.create(req)

    async def get_incoming(
        self, user_id: int, status_filter: Optional[str] = None
    ) -> List[SparringRequest]:
        stmt = (
            select(SparringRequest)
            .options(
                selectinload(SparringRequest.requester),
                selectinload(SparringRequest.recipient),
            )
            .where(SparringRequest.recipient_id == user_id)
            .order_by(SparringRequest.created_at.desc())
        )
        if status_filter:
            stmt = stmt.where(SparringRequest.status == status_filter)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_outgoing(
        self, user_id: int, status_filter: Optional[str] = None
    ) -> List[SparringRequest]:
        stmt = (
            select(SparringRequest)
            .options(
                selectinload(SparringRequest.requester),
                selectinload(SparringRequest.recipient),
            )
            .where(SparringRequest.requester_id == user_id)
            .order_by(SparringRequest.created_at.desc())
        )
        if status_filter:
            stmt = stmt.where(SparringRequest.status == status_filter)
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_combat_matches(
        self, user_id: int, limit: int = 20
    ) -> List[UserSportProfile]:
        """
        Candidate pool for match suggestions: every 'combat' UserSportProfile
        except the current user's own. Filtering on the actual criteria
        (discipline / weight_class / belt_rank, all stored inside the JSON
        `attributes` column) happens in Python at the endpoint layer rather
        than via JSON operators in SQL — the same cross-dialect-safety
        principle already used for validate_sport_attributes(), since
        `attributes` is JSONB on Postgres but plain JSON on SQLite in dev
        (see app/models/sport.py:FlexibleJSON).

        `limit * 5` is fetched so the Python-side filter still has enough
        candidates left to return up to `limit` real matches.
        """
        result = await self.db.execute(
            select(UserSportProfile)
            .join(Sport, UserSportProfile.sport_id == Sport.id)
            .options(
                selectinload(UserSportProfile.user),
                selectinload(UserSportProfile.sport),
            )
            .where(Sport.slug == "combat", UserSportProfile.user_id != user_id)
            .limit(limit * 5)
        )
        return list(result.scalars().all())
