from typing import Optional, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.exercise import Exercise, ExerciseCategory, DifficultyLevel
from app.repositories.base_repository import BaseRepository


class ExerciseRepository(BaseRepository[Exercise]):

    def __init__(self, db: AsyncSession):
        super().__init__(Exercise, db)

    async def filter_exercises(
        self,
        category: Optional[ExerciseCategory] = None,
        difficulty: Optional[DifficultyLevel] = None,
        sport_type: Optional[str] = None,
        search: Optional[str] = None,
        skip: int = 0,
        limit: int = 20,
    ) -> List[Exercise]:
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
