from sqlalchemy import Column, Integer, String, Text, Enum, Float, DateTime, func, ARRAY
from app.core.database import Base
import enum


class ExerciseCategory(str, enum.Enum):
    EXPLOSIVE_POWER = "Explosive Power"
    STRENGTH = "Strength"
    ENDURANCE = "Endurance"
    FLEXIBILITY = "Flexibility"
    TECHNIQUE = "Technique"
    SPARRING = "Sparring"
    CONDITIONING = "Conditioning"


class DifficultyLevel(str, enum.Enum):
    BEGINNER = "Beginner"
    INTERMEDIATE = "Intermediate"
    ADVANCED = "Advanced"
    ELITE = "Elite"


class Exercise(Base):
    __tablename__ = "exercises"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False, index=True)
    name_ar = Column(String(100), nullable=True)  # Arabic name
    category = Column(Enum(ExerciseCategory), nullable=False)
    difficulty = Column(Enum(DifficultyLevel), nullable=False)

    description = Column(Text, nullable=False)
    instructions = Column(Text, nullable=False)   # Step-by-step JSON string
    muscles_targeted = Column(String(300), nullable=True)  # e.g., "Legs, Core, Shoulders"
    sport_types = Column(String(300), nullable=True)       # e.g., "MMA, Boxing, BJJ"

    # Media
    video_url = Column(String(500), nullable=True)
    thumbnail_url = Column(String(500), nullable=True)

    # Metrics
    sets_recommended = Column(String(50), nullable=True)   # e.g., "3-5"
    reps_recommended = Column(String(50), nullable=True)   # e.g., "5-8"
    rest_seconds = Column(Integer, nullable=True)

    # Equipment
    equipment_needed = Column(String(300), nullable=True)  # e.g., "Barbell, Box"

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    def __repr__(self) -> str:
        return f"<Exercise {self.name} | {self.category}>"
