from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.models.exercise import Exercise, ExerciseCategory, DifficultyLevel
from app.repositories.exercise_repository import ExerciseRepository
from app.schemas.exercise import ExerciseCreate, ExerciseResponse

router = APIRouter(prefix="/exercises", tags=["Exercise Library"])


@router.get("/", response_model=List[ExerciseResponse])
async def list_exercises(
    category: Optional[ExerciseCategory] = None,
    difficulty: Optional[DifficultyLevel] = None,
    sport_type: Optional[str] = None,
    search: Optional[str] = None,
    skip: int = 0,
    limit: int = 20,
    db: AsyncSession = Depends(get_db),
):
    repo = ExerciseRepository(db)
    return await repo.filter_exercises(
        category=category,
        difficulty=difficulty,
        sport_type=sport_type,
        search=search,
        skip=skip,
        limit=limit,
    )


@router.get("/{exercise_id}", response_model=ExerciseResponse)
async def get_exercise(exercise_id: int, db: AsyncSession = Depends(get_db)):
    repo = ExerciseRepository(db)
    exercise = await repo.get_by_id(exercise_id)
    if not exercise:
        raise HTTPException(status_code=404, detail="Exercise not found")
    return exercise


@router.post("/", response_model=ExerciseResponse, status_code=status.HTTP_201_CREATED)
async def create_exercise(
    payload: ExerciseCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    # Only coaches can add exercises
    if not current_user.is_coach:
        raise HTTPException(status_code=403, detail="Only coaches can add exercises")

    repo = ExerciseRepository(db)
    exercise = Exercise(**payload.model_dump())
    created = await repo.create(exercise)
    await db.commit()
    await db.refresh(created)
    return created
