"""
v6 — Sparring matching system.

SparringRequest is the single table backing both flows agreed on for v6:
  1) Manual request/accept between two users (any user can request any
     other user directly).
  2) Automatic match suggestions (see SparringRepository.get_combat_matches
     + the /sparring/suggestions endpoint), which surface candidates by
     comparing `UserSportProfile.attributes` (discipline, weight_class,
     belt_rank) for the 'combat' sport — suggestions never write a row
     here by themselves, they only recommend who to send a manual
     request to.

Scheduling (scheduled_at + location) is included per the agreed scope.
`gym_id` / `open_mat_id` (added in v7, now that the `gyms` / `open_mats`
tables exist — see the v6 SparringRequest docstring history) let a
request optionally be anchored to a specific gym and/or open mat instead
of (or alongside) a free-text `location`. Both stay nullable: a sparring
request between two users doesn't have to involve a gym at all.

`status` is a plain indexed VARCHAR rather than a native Postgres ENUM —
same convention as `PostReaction.reaction_type` in app/models/post.py —
so adding a new status later is a Python-only change with no ALTER TYPE
migration. Validation of the allowed values happens at the Pydantic layer
(see app/schemas/sparring.py: SparringStatus / SparringRequestAction).
"""
from sqlalchemy import Column, Integer, String, Text, ForeignKey, DateTime, func
from sqlalchemy.orm import relationship
from app.core.database import Base


class SparringRequest(Base):
    __tablename__ = "sparring_requests"

    id = Column(Integer, primary_key=True, index=True)
    requester_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    recipient_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # pending | accepted | declined | cancelled | completed
    status = Column(String(20), nullable=False, default="pending", index=True)

    message = Column(Text, nullable=True)
    scheduled_at = Column(DateTime(timezone=True), nullable=True)
    location = Column(String(200), nullable=True)  # free text, used when no gym_id is set

    # v7: optional anchor to a specific gym and/or open mat.
    gym_id = Column(Integer, ForeignKey("gyms.id", ondelete="SET NULL"), nullable=True, index=True)
    open_mat_id = Column(Integer, ForeignKey("open_mats.id", ondelete="SET NULL"), nullable=True, index=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # No back_populates on User (mirrors Conversation.user_1/user_2 in
    # app/models/message.py) — keeps this feature additive without
    # touching app/models/user.py.
    requester = relationship("User", foreign_keys=[requester_id])
    recipient = relationship("User", foreign_keys=[recipient_id])
    gym = relationship("Gym", foreign_keys=[gym_id])
    open_mat = relationship("OpenMat", foreign_keys=[open_mat_id])

    def __repr__(self) -> str:
        return f"<SparringRequest {self.requester_id}->{self.recipient_id} [{self.status}]>"
