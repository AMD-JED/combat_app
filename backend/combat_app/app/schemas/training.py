import enum
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class TrainingSessionType(str, enum.Enum):
    SOLO = "solo"
    CLASS = "class"
    SPARRING = "sparring"
    CONDITIONING = "conditioning"
    TECHNIQUE = "technique"
    OTHER = "other"


# ──────────────────────────────────────────────
#  Exercise log (optional, nested detail)
# ──────────────────────────────────────────────

class TrainingExerciseLogCreate(BaseModel):
    exercise_id: Optional[int] = None
    sets: Optional[int] = Field(None, ge=0)
    reps: Optional[int] = Field(None, ge=0)
    weight_kg: Optional[float] = Field(None, ge=0)
    duration_seconds: Optional[int] = Field(None, ge=0)
    order_index: int = 0
    notes: Optional[str] = Field(None, max_length=500)


class TrainingExerciseLogResponse(BaseModel):
    id: int
    exercise_id: Optional[int] = None
    sets: Optional[int] = None
    reps: Optional[int] = None
    weight_kg: Optional[float] = None
    duration_seconds: Optional[int] = None
    order_index: int
    notes: Optional[str] = None
    analysis_job_id: Optional[str] = None

    model_config = {"from_attributes": True}


# ──────────────────────────────────────────────
#  Session
# ──────────────────────────────────────────────

class TrainingSessionCreate(BaseModel):
    session_type: TrainingSessionType
    duration_minutes: int = Field(..., gt=0, le=1440)
    intensity: Optional[int] = Field(None, ge=1, le=5)
    notes: Optional[str] = Field(None, max_length=1000)
    session_date: Optional[datetime] = None  # defaults to now() at the DB layer if omitted

    sport_id: Optional[int] = None
    gym_id: Optional[int] = None
    sparring_request_id: Optional[int] = None

    exercises: Optional[List[TrainingExerciseLogCreate]] = None


class TrainingSessionUpdate(BaseModel):
    session_type: Optional[TrainingSessionType] = None
    duration_minutes: Optional[int] = Field(None, gt=0, le=1440)
    intensity: Optional[int] = Field(None, ge=1, le=5)
    notes: Optional[str] = Field(None, max_length=1000)
    session_date: Optional[datetime] = None
    sport_id: Optional[int] = None
    gym_id: Optional[int] = None
    sparring_request_id: Optional[int] = None


class TrainingSessionResponse(BaseModel):
    id: int
    user_id: int
    sport_id: Optional[int] = None
    session_type: TrainingSessionType
    duration_minutes: int
    intensity: Optional[int] = None
    notes: Optional[str] = None
    session_date: datetime
    gym_id: Optional[int] = None
    sparring_request_id: Optional[int] = None
    created_at: datetime
    updated_at: Optional[datetime] = None
    exercise_logs: List[TrainingExerciseLogResponse] = []

    model_config = {"from_attributes": True}


class TrainingSessionSummary(BaseModel):
    """Lightweight shape used for list views and for injecting recent
    training history into the AI Coach context — avoids serializing the
    full nested exercise_logs for every session in a list."""
    id: int
    session_type: TrainingSessionType
    duration_minutes: int
    intensity: Optional[int] = None
    session_date: datetime
    gym_id: Optional[int] = None

    model_config = {"from_attributes": True}
