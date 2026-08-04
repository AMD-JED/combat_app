from sqlalchemy import Column, Integer, String, Text, ForeignKey, DateTime, func, Table, Enum
from sqlalchemy.orm import relationship
from app.core.database import Base
import enum


class PostType(str, enum.Enum):
    TEXT = "text"
    IMAGE = "image"
    VIDEO = "video"


# Association table for post likes
post_likes = Table(
    "post_likes",
    Base.metadata,
    Column("user_id", Integer, ForeignKey("users.id"), primary_key=True),
    Column("post_id", Integer, ForeignKey("posts.id"), primary_key=True),
)


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
    liked_by = relationship("User", secondary=post_likes)


class Comment(Base):
    __tablename__ = "comments"

    id = Column(Integer, primary_key=True, index=True)
    post_id = Column(Integer, ForeignKey("posts.id"), nullable=False)
    author_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    content = Column(Text, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    post = relationship("Post", back_populates="comments")
    author = relationship("User")
