"""
Message Models
==============
Two tables:
  - conversations: a chat between exactly 2 users (DM)
  - messages: individual messages inside a conversation

Design decisions:
  - Conversations are identified by a sorted pair of user IDs
    so (user_1=3, user_2=7) and (user_1=7, user_2=3) always
    resolve to the same row.
  - Messages store is_read so the client can show unread badges.
  - deleted_at soft-delete so "You deleted this message" UX works.
"""

from sqlalchemy import (
    Column, Integer, String, Text, Boolean,
    ForeignKey, DateTime, func, UniqueConstraint
)
from sqlalchemy.orm import relationship
from app.core.database import Base


class Conversation(Base):
    __tablename__ = "conversations"

    id = Column(Integer, primary_key=True, index=True)

    # Always store lower ID first to avoid duplicates
    user_1_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    user_2_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    last_message_at = Column(DateTime(timezone=True), server_default=func.now())

    # Ensure one conversation per pair
    __table_args__ = (
        UniqueConstraint("user_1_id", "user_2_id", name="uq_conversation_pair"),
    )

    user_1 = relationship("User", foreign_keys=[user_1_id])
    user_2 = relationship("User", foreign_keys=[user_2_id])
    messages = relationship(
        "Message",
        back_populates="conversation",
        cascade="all, delete-orphan",
        order_by="Message.created_at",
    )

    def other_user(self, current_user_id: int):
        return self.user_2 if self.user_1_id == current_user_id else self.user_1


class Message(Base):
    __tablename__ = "messages"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(Integer, ForeignKey("conversations.id"), nullable=False, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    content = Column(Text, nullable=True)           # Text message
    media_url = Column(String(500), nullable=True)  # Image/video from Cloudinary
    media_type = Column(String(20), nullable=True)  # "image" | "video"

    # v9 — set when this message is a reply to a Story (see
    # POST /stories/{id}/reply). SET NULL on story delete/expiry-cleanup
    # so the message itself is never lost, just loses the story context.
    reply_to_story_id = Column(Integer, ForeignKey("stories.id", ondelete="SET NULL"), nullable=True, index=True)

    is_read = Column(Boolean, default=False)
    deleted_at = Column(DateTime(timezone=True), nullable=True)  # Soft delete

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    conversation = relationship("Conversation", back_populates="messages")
    sender = relationship("User", foreign_keys=[sender_id])
    reply_to_story = relationship("Story", foreign_keys=[reply_to_story_id])
