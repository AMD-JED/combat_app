"""
v8 — Personal training tracking.

TrainingSession is the general log entry for one training session
(solo work, a class, sparring, conditioning, etc). It's intentionally
"light" on its own — type, duration, intensity, notes — and can
optionally be anchored to a `gym_id` and/or `sparring_request_id`
(both nullable), closing the loop the user asked for: a session can be
tied to "I trained at this gym" and/or "this was the session with my
sparring partner from that accepted request".

TrainingExerciseLog is the optional, more detailed breakdown of a
session: individual entries from the existing `Exercise` library with
sets/reps/weight. A session can have zero, one, or many of these —
logging a session doesn't require picking exercises.

`session_type` is a plain indexed VARCHAR rather than a native Postgres
ENUM — same convention as `SparringRequest.status` / `GymMembership.role`
— so adding a new type later is a Python-only change with no ALTER TYPE
migration. Validation of the allowed values happens at the Pydantic layer
(see app/schemas/training.py: TrainingSessionType).

`analysis_job_id` is a nullable forward-compatible hook: it does nothing
today, but reserves a place to attach the result of a future pose/CV
analysis job (e.g. a punch-technique analyzer running as an independent
microservice) to a specific exercise log entry, without needing a schema
change later.
"""
from sqlalchemy import (
    Column,
    Integer,
    String,
    Text,
    Float,
    ForeignKey,
    DateTime,
    func,
)
from sqlalchemy.orm import relationship

from app.core.database import Base


class TrainingSession(Base):
    __tablename__ = "training_sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    sport_id = Column(Integer, ForeignKey("sports.id", ondelete="SET NULL"), nullable=True, index=True)

    # solo | class | sparring | conditioning | technique | other
    session_type = Column(String(30), nullable=False, index=True)

    duration_minutes = Column(Integer, nullable=False)
    intensity = Column(Integer, nullable=True)  # 1-5, validated at the Pydantic layer
    notes = Column(Text, nullable=True)
    session_date = Column(DateTime(timezone=True), nullable=False, server_default=func.now())

    # Optional anchors — a session doesn't have to involve a gym or a
    # sparring partner at all.
    gym_id = Column(Integer, ForeignKey("gyms.id", ondelete="SET NULL"), nullable=True, index=True)
    sparring_request_id = Column(
        Integer, ForeignKey("sparring_requests.id", ondelete="SET NULL"), nullable=True, index=True
    )

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # No back_populates on User/Gym/SparringRequest — mirrors the
    # SparringRequest <-> Gym/OpenMat convention (keeps this feature
    # additive without touching those model files).
    user = relationship("User", foreign_keys=[user_id])
    sport = relationship("Sport", foreign_keys=[sport_id])
    gym = relationship("Gym", foreign_keys=[gym_id])
    sparring_request = relationship("SparringRequest", foreign_keys=[sparring_request_id])

    exercise_logs = relationship(
        "TrainingExerciseLog",
        back_populates="session",
        cascade="all, delete-orphan",
        order_by="TrainingExerciseLog.order_index",
    )

    def __repr__(self) -> str:
        return f"<TrainingSession user={self.user_id} type={self.session_type}>"


class TrainingExerciseLog(Base):
    __tablename__ = "training_exercise_logs"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(
        Integer, ForeignKey("training_sessions.id", ondelete="CASCADE"), nullable=False, index=True
    )
    exercise_id = Column(Integer, ForeignKey("exercises.id", ondelete="SET NULL"), nullable=True, index=True)

    sets = Column(Integer, nullable=True)
    reps = Column(Integer, nullable=True)
    weight_kg = Column(Float, nullable=True)
    duration_seconds = Column(Integer, nullable=True)  # for timed work, e.g. bag rounds
    order_index = Column(Integer, nullable=False, default=0)
    notes = Column(Text, nullable=True)

    # v8 forward-compat hook — unused today, reserved for a future CV/pose
    # analysis microservice result to attach to this specific log entry.
    analysis_job_id = Column(String(100), nullable=True, index=True)

    session = relationship("TrainingSession", back_populates="exercise_logs")
    exercise = relationship("Exercise", foreign_keys=[exercise_id])

    def __repr__(self) -> str:
        return f"<TrainingExerciseLog session={self.session_id} exercise={self.exercise_id}>"
