from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.repositories.exercise_repository import ExerciseRepository
from app.repositories.gym_repository import GymRepository
from app.repositories.sparring_repository import SparringRepository
from app.repositories.sport_repository import SportRepository
from app.repositories.training_repository import TrainingRepository
from app.schemas.training import (
    TrainingSessionCreate,
    TrainingSessionResponse,
    TrainingSessionSummary,
)

router = APIRouter(prefix="/training", tags=["Training"])


async def _validate_optional_links(
    payload: TrainingSessionCreate, current_user: User, db: AsyncSession
) -> None:
    if payload.sport_id is not None:
        sport_repo = SportRepository(db)
        sport = await sport_repo.get_by_id(payload.sport_id)
        if not sport:
            raise HTTPException(status_code=404, detail="Sport not found")

    if payload.gym_id is not None:
        gym_repo = GymRepository(db)
        gym = await gym_repo.get_by_id(payload.gym_id)
        if not gym or not gym.is_active:
            raise HTTPException(status_code=404, detail="Gym not found")

    if payload.sparring_request_id is not None:
        sparring_repo = SparringRepository(db)
        req = await sparring_repo.get_by_id(payload.sparring_request_id)
        if not req:
            raise HTTPException(status_code=404, detail="Sparring request not found")
        if current_user.id not in (req.requester_id, req.recipient_id):
            raise HTTPException(
                status_code=403,
                detail="You can only link a session to a sparring request you're part of",
            )

    if payload.exercises:
        exercise_repo = ExerciseRepository(db)
        for ex in payload.exercises:
            if ex.exercise_id is not None:
                exercise = await exercise_repo.get_by_id(ex.exercise_id)
                if not exercise:
                    raise HTTPException(
                        status_code=404, detail=f"Exercise not found: id={ex.exercise_id}"
                    )


@router.post("/sessions", response_model=TrainingSessionResponse, status_code=status.HTTP_201_CREATED)
async def create_training_session(
    payload: TrainingSessionCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    await _validate_optional_links(payload, current_user, db)

    training_repo = TrainingRepository(db)
    session = await training_repo.create_session_with_exercises(
        user_id=current_user.id,
        session_type=payload.session_type.value,
        duration_minutes=payload.duration_minutes,
        intensity=payload.intensity,
        notes=payload.notes,
        session_date=payload.session_date,
        sport_id=payload.sport_id,
        gym_id=payload.gym_id,
        sparring_request_id=payload.sparring_request_id,
        exercises=[e.model_dump() for e in payload.exercises] if payload.exercises else None,
    )
    await db.commit()
    return await training_repo.get_with_exercises(session.id)


@router.get("/sessions", response_model=List[TrainingSessionSummary])
async def list_training_sessions(
    sport_id: Optional[int] = None,
    session_type: Optional[str] = None,
    skip: int = 0,
    limit: int = 20,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    training_repo = TrainingRepository(db)
    return await training_repo.get_user_sessions(
        current_user.id,
        sport_id=sport_id,
        session_type=session_type,
        skip=skip,
        limit=limit,
    )


@router.get("/sessions/{session_id}", response_model=TrainingSessionResponse)
async def get_training_session(
    session_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    training_repo = TrainingRepository(db)
    session = await training_repo.get_with_exercises(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Training session not found")
    if session.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized to view this session")
    return session


@router.delete("/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_training_session(
    session_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    training_repo = TrainingRepository(db)
    session = await training_repo.get_by_id(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Training session not found")
    if session.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized to delete this session")

    await training_repo.delete(session_id)
    await db.commit()
    return None
