from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from app.models.exercise import ExerciseCategory, DifficultyLevel


class ExerciseCreate(BaseModel):
    name: str = Field(..., max_length=100)
    name_ar: Optional[str] = Field(None, max_length=100)
    category: ExerciseCategory
    difficulty: DifficultyLevel
    description: str
    instructions: str
    muscles_targeted: Optional[str] = None
    sport_types: Optional[str] = None
    video_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    sets_recommended: Optional[str] = None
    reps_recommended: Optional[str] = None
    rest_seconds: Optional[int] = None
    equipment_needed: Optional[str] = None


class ExerciseResponse(ExerciseCreate):
    id: int
    created_at: datetime

    model_config = {"from_attributes": True}


class ExerciseFilter(BaseModel):
    category: Optional[ExerciseCategory] = None
    difficulty: Optional[DifficultyLevel] = None
    sport_type: Optional[str] = None
    search: Optional[str] = None
