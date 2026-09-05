from datetime import datetime
from typing import List, Optional

from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.training import TrainingSession, TrainingExerciseLog
from app.repositories.base_repository import BaseRepository


class TrainingRepository(BaseRepository[TrainingSession]):

    def __init__(self, db: AsyncSession):
        super().__init__(TrainingSession, db)

    async def create_session_with_exercises(
        self,
        *,
        user_id: int,
        session_type: str,
        duration_minutes: int,
        intensity: Optional[int],
        notes: Optional[str],
        session_date: Optional[datetime],
        sport_id: Optional[int],
        gym_id: Optional[int],
        sparring_request_id: Optional[int],
        exercises: Optional[List[dict]],
    ) -> TrainingSession:
        session = TrainingSession(
            user_id=user_id,
            session_type=session_type,
            duration_minutes=duration_minutes,
            intensity=intensity,
            notes=notes,
            sport_id=sport_id,
            gym_id=gym_id,
            sparring_request_id=sparring_request_id,
        )
        if session_date is not None:
            session.session_date = session_date

        if exercises:
            for order, ex in enumerate(exercises):
                session.exercise_logs.append(
                    TrainingExerciseLog(
                        exercise_id=ex.get("exercise_id"),
                        sets=ex.get("sets"),
                        reps=ex.get("reps"),
                        weight_kg=ex.get("weight_kg"),
                        duration_seconds=ex.get("duration_seconds"),
                        order_index=ex.get("order_index", order),
                        notes=ex.get("notes"),
                    )
                )

        self.db.add(session)
        await self.db.flush()
        await self.db.refresh(session)
        return session

    async def get_with_exercises(self, session_id: int) -> Optional[TrainingSession]:
        result = await self.db.execute(
            select(TrainingSession)
            .options(selectinload(TrainingSession.exercise_logs))
            .where(TrainingSession.id == session_id)
        )
        return result.scalar_one_or_none()

    async def get_user_sessions(
        self,
        user_id: int,
        *,
        sport_id: Optional[int] = None,
        session_type: Optional[str] = None,
        skip: int = 0,
        limit: int = 20,
    ) -> List[TrainingSession]:
        query = (
            select(TrainingSession)
            .options(selectinload(TrainingSession.exercise_logs))
            .where(TrainingSession.user_id == user_id)
        )
        if sport_id is not None:
            query = query.where(TrainingSession.sport_id == sport_id)
        if session_type is not None:
            query = query.where(TrainingSession.session_type == session_type)

        query = query.order_by(desc(TrainingSession.session_date)).offset(skip).limit(limit)
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def get_recent_for_context(self, user_id: int, limit: int = 5) -> List[TrainingSession]:
        """Lightweight recent-history fetch used by the AI Coach context
        builder — no exercise_logs eager-load needed there."""
        result = await self.db.execute(
            select(TrainingSession)
            .where(TrainingSession.user_id == user_id)
            .order_by(desc(TrainingSession.session_date))
            .limit(limit)
        )
        return list(result.scalars().all())
