"""
v7 — Open Mats.

An OpenMat belongs to exactly one Gym and is either:
  - one-time: `event_datetime` is set (a specific date+time), or
  - recurring (weekly): `recurrence_day` + `start_time` are set instead.
Exactly one of these two shapes must be provided — enforced in
app/schemas/open_mat.py:OpenMatCreate, not at the DB layer, so both sets
of columns are nullable here.

Known v7 simplification (documented rather than silently glossed over):
RSVP is tracked per OpenMat, not per individual occurrence of a recurring
event. For a weekly open mat, "going" means "I plan to attend the
recurring session generally" — there's no per-Saturday attendee list yet.
Per-occurrence RSVPs would need an `OpenMatOccurrence` concept and are
deferred to a future version if the product actually needs them.

`location_override` lets an open mat specify a different spot than the
gym's own `location` (e.g. an outdoor session) — resolved to
"location_override or gym.location" at the API layer, not stored twice.
"""
from sqlalchemy import (
    Column,
    Integer,
    String,
    Text,
    Boolean,
    ForeignKey,
    DateTime,
    Time,
    func,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from app.core.database import Base


class OpenMat(Base):
    __tablename__ = "open_mats"

    id = Column(Integer, primary_key=True, index=True)
    gym_id = Column(Integer, ForeignKey("gyms.id", ondelete="CASCADE"), nullable=False, index=True)
    created_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    title = Column(String(150), nullable=False)
    description = Column(Text, nullable=True)

    is_recurring = Column(Boolean, nullable=False, default=False)

    # One-time events:
    event_datetime = Column(DateTime(timezone=True), nullable=True)

    # Recurring (weekly) events — recurrence_day is a lowercase weekday
    # string ("monday".."sunday"), validated at the schema layer
    # (app/schemas/open_mat.py:RecurrenceDay).
    recurrence_day = Column(String(10), nullable=True)
    start_time = Column(Time, nullable=True)
    end_time = Column(Time, nullable=True)

    location_override = Column(String(200), nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    gym = relationship("Gym", back_populates="open_mats")
    creator = relationship("User", foreign_keys=[created_by])
    rsvps = relationship("OpenMatRSVP", back_populates="open_mat", cascade="all, delete-orphan")

    def __repr__(self) -> str:
        return f"<OpenMat {self.title!r} gym={self.gym_id}>"


class OpenMatRSVP(Base):
    __tablename__ = "open_mat_rsvps"
    __table_args__ = (UniqueConstraint("open_mat_id", "user_id", name="uq_open_mat_user"),)

    id = Column(Integer, primary_key=True, index=True)
    open_mat_id = Column(Integer, ForeignKey("open_mats.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    open_mat = relationship("OpenMat", back_populates="rsvps")
    user = relationship("User", foreign_keys=[user_id])

    def __repr__(self) -> str:
        return f"<OpenMatRSVP open_mat={self.open_mat_id} user={self.user_id}>"
