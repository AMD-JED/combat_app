"""
v7 — Gyms.

A Gym is an informational directory entry (name/location/description/
sports offered) that has exactly one owner (the user who created it, or
whoever an existing owner transfers it to — transfer is out of scope for
v7) plus a membership list. Membership is a simple direct-join model, no
approval workflow: any authenticated user can join a gym as `member`.
The owner is always also a `GymMembership` row with role='owner' (created
automatically alongside the Gym itself), so member listings are complete
without special-casing the owner.

`role` is a plain indexed VARCHAR — same convention as
SparringRequest.status / PostReaction.reaction_type — so adding a role
later (e.g. promoting a member to 'coach') never needs an ALTER TYPE
migration; see GymRole in app/schemas/gym.py for the Pydantic-side
validation of allowed values.

`sports` reuses the FlexibleJSON type already defined for
UserSportProfile.attributes (JSONB on Postgres, plain JSON on SQLite) —
it's a simple list of Sport.slug strings the gym offers, e.g.
["combat", "running"].
"""
from sqlalchemy import (
    Column,
    Integer,
    String,
    Text,
    Boolean,
    ForeignKey,
    DateTime,
    func,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from app.core.database import Base
from app.models.sport import FlexibleJSON


class Gym(Base):
    __tablename__ = "gyms"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)

    name = Column(String(150), nullable=False, index=True)
    description = Column(Text, nullable=True)
    location = Column(String(200), nullable=True)
    sports = Column(FlexibleJSON, nullable=False, default=list)  # list[str] of Sport.slug

    contact_phone = Column(String(30), nullable=True)
    contact_email = Column(String(255), nullable=True)

    is_active = Column(Boolean, nullable=False, default=True)  # soft-delete flag

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    owner = relationship("User", foreign_keys=[owner_id])
    memberships = relationship("GymMembership", back_populates="gym", cascade="all, delete-orphan")
    open_mats = relationship("OpenMat", back_populates="gym", cascade="all, delete-orphan")

    def __repr__(self) -> str:
        return f"<Gym {self.name!r}>"


class GymMembership(Base):
    __tablename__ = "gym_memberships"
    __table_args__ = (UniqueConstraint("gym_id", "user_id", name="uq_gym_user"),)

    id = Column(Integer, primary_key=True, index=True)
    gym_id = Column(Integer, ForeignKey("gyms.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # owner | coach | member — see app/schemas/gym.py:GymRole
    role = Column(String(20), nullable=False, default="member", index=True)

    joined_at = Column(DateTime(timezone=True), server_default=func.now())

    gym = relationship("Gym", back_populates="memberships")
    user = relationship("User", foreign_keys=[user_id])

    def __repr__(self) -> str:
        return f"<GymMembership gym={self.gym_id} user={self.user_id} role={self.role}>"
