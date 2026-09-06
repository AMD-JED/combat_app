from sqlalchemy import Column, Integer, String, Text, ForeignKey, DateTime, func, Enum, UniqueConstraint, CheckConstraint
from sqlalchemy.orm import relationship
from app.core.database import Base
import enum


class PostType(str, enum.Enum):
    TEXT = "text"
    IMAGE = "image"
    VIDEO = "video"


class ReactionType(str, enum.Enum):
    """
    v5 — Athletes Hub rich reactions (replaces the old plain post_likes
    like/unlike toggle). Mirrors `ReactionType` in the React prototype's
    src/types.ts exactly, since that prototype is now the source of truth
    for what the frontend expects to send/receive here.
    """
    RESPECT = "respect"
    FIRE = "fire"
    STRENGTH = "strength"
    PRECISION = "precision"
    CHAMPION = "champion"
    SPORT = "sport"


class Post(Base):
    __tablename__ = "posts"

    id = Column(Integer, primary_key=True, index=True)
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    content = Column(Text, nullable=True)
    media_url = Column(String(500), nullable=True)
    post_type = Column(Enum(PostType), default=PostType.TEXT)
    tags = Column(String(500), nullable=True)  # comma-separated tags e.g., "#MMA,#Training"

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relationships
    author = relationship("User", back_populates="posts")
    comments = relationship("Comment", back_populates="post", cascade="all, delete-orphan")
    reactions = relationship("PostReaction", back_populates="post", cascade="all, delete-orphan")


class PostReaction(Base):
    """
    One row per (post, user) — a user has exactly ONE active reaction per
    post at a time (switching reaction types overwrites the row; reacting
    again with the same type removes it — see
    PostRepository.react_to_post). This fully replaces the old `post_likes`
    association table; existing likes are migrated into `fire` reactions
    by the v5 Alembic migration.

    NOTE: `reaction_type` is a plain indexed String, not a native Postgres
    ENUM type — validation of the 6 allowed values happens at the Pydantic
    layer (schemas.post.ReactionCreate). This keeps future changes to the
    reaction set a simple Python-only change with no ALTER TYPE migration.
    """
    __tablename__ = "post_reactions"
    __table_args__ = (
        UniqueConstraint("post_id", "user_id", name="uq_post_reactions_post_user"),
    )

    id = Column(Integer, primary_key=True, index=True)
    post_id = Column(Integer, ForeignKey("posts.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    reaction_type = Column(String(20), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    post = relationship("Post", back_populates="reactions")
    user = relationship("User")


class Comment(Base):
    """
    v9 — Comment now targets EITHER a Post OR a Reel, never both and
    never neither. Rather than a fully generic polymorphic design
    (commentable_type/commentable_id), this project's convention favors
    plain direct FK columns (see reaction_type / session_type docstrings
    elsewhere) — so `reel_id` was added as a second nullable FK alongside
    the now-nullable `post_id`, enforced by a CHECK constraint at the DB
    level. This was a safer migration (one ADD COLUMN + one loosened
    NOT NULL) than restructuring the table around a generic key.
    """
    __tablename__ = "comments"
    __table_args__ = (
        CheckConstraint(
            "(post_id IS NOT NULL) != (reel_id IS NOT NULL)",
            name="ck_comments_exactly_one_target",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    post_id = Column(Integer, ForeignKey("posts.id", ondelete="CASCADE"), nullable=True, index=True)
    reel_id = Column(Integer, ForeignKey("reels.id", ondelete="CASCADE"), nullable=True, index=True)
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    content = Column(Text, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    post = relationship("Post", back_populates="comments")
    reel = relationship("Reel", back_populates="comments")
    author = relationship("User")
