"""
v9 — Reels.

A Reel is a short-form video, deliberately modeled as its own table
rather than a `Post` with `post_type='reel'` (architectural decision
confirmed during v9 scoping): Reels have their own feed algorithm
(filtered by `sport_id`, not a chronological following-based feed like
`Post.feed`), their own view-count/duration fields that would sit empty
on every non-reel `Post` row, and a natural place to attach a future
CV/pose-analysis job result — same forward-compat pattern as
`TrainingExerciseLog.analysis_job_id` (see app/models/training.py).

Anyone can post a Reel (no coach-only restriction, unlike exercise
tutorial videos) — coach authorship is simply surfaced to the client as
a badge by looking at `author.is_coach` at serialization time (see
app/schemas/reel.py:ReelResponse.is_coach_content), not enforced here.

Reactions on Reels are a simple like/unlike (`ReelLike`) — NOT the six
Athletes Hub reaction types on `Post` (confirmed decision) — kept as its
own table (not reusing `PostReaction`) since `PostReaction.post_id` is a
required FK to `posts.id` and reusing it for reels would need the same
kind of dual-nullable-FK change made to `Comment` below, which isn't
justified here since Reels don't need the 6-way reaction_type richness.

Comments on Reels reuse the existing `Comment` model (see
app/models/post.py) via a new nullable `reel_id` column — a polymorphic-
by-dual-FK design (confirmed decision), rather than a separate
`reel_comments` table.
"""
from sqlalchemy import (
    Column,
    Integer,
    String,
    Text,
    DateTime,
    ForeignKey,
    func,
    UniqueConstraint,
)
from sqlalchemy.orm import relationship

from app.core.database import Base


class Reel(Base):
    __tablename__ = "reels"

    id = Column(Integer, primary_key=True, index=True)
    author_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    media_url = Column(String(500), nullable=False)
    thumbnail_url = Column(String(500), nullable=True)
    caption = Column(Text, nullable=True)

    # Feed filter — v9 decision: Reels feed is filtered by sport, not a
    # following-based chronological feed like Post.feed.
    sport_id = Column(Integer, ForeignKey("sports.id", ondelete="SET NULL"), nullable=True, index=True)

    duration_seconds = Column(Integer, nullable=True)
    view_count = Column(Integer, nullable=False, default=0)

    # v9 forward-compat hook — unused today, reserved for a future CV/pose
    # analysis microservice result to attach to this specific reel. Mirrors
    # TrainingExerciseLog.analysis_job_id.
    analysis_job_id = Column(String(100), nullable=True, index=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    author = relationship("User", foreign_keys=[author_id])
    sport = relationship("Sport", foreign_keys=[sport_id])
    likes = relationship("ReelLike", back_populates="reel", cascade="all, delete-orphan")
    comments = relationship("Comment", back_populates="reel", cascade="all, delete-orphan")

    def __repr__(self) -> str:
        return f"<Reel author={self.author_id} sport={self.sport_id}>"


class ReelLike(Base):
    """Simple like/unlike toggle — one row per (reel, user). Deliberately
    NOT the six-reaction-type PostReaction model (confirmed v9 decision)."""
    __tablename__ = "reel_likes"
    __table_args__ = (
        UniqueConstraint("reel_id", "user_id", name="uq_reel_likes_reel_user"),
    )

    id = Column(Integer, primary_key=True, index=True)
    reel_id = Column(Integer, ForeignKey("reels.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    reel = relationship("Reel", back_populates="likes")
    user = relationship("User", foreign_keys=[user_id])

    def __repr__(self) -> str:
        return f"<ReelLike reel={self.reel_id} user={self.user_id}>"
