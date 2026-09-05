"""
v8 — AI Coach conversations.

Multi-thread, named conversations (ChatGPT-style) — a user can have many
AICoachConversation rows, each holding its own ordered list of messages.
This is deliberately a *separate* table from app/models/message.py
(Conversation/Message, used for user<->user direct messaging): the AI
Coach is not a person, has a different lifecycle (no "unread" state, no
two-party membership), and keeping it separate means neither feature's
migrations or queries need to special-case the other.

`role` on AICoachMessage is a plain indexed VARCHAR ("user" | "assistant")
— same convention as SparringRequest.status / GymMembership.role — so
there's no ALTER TYPE cost if a future role (e.g. "system") is added.

The actual call to the AI provider (Gemini today, swappable later — see
app/services/gemini_service.py) happens in the endpoint/service layer,
not here. This model only persists the conversation; it has no opinion
about which provider produced an "assistant" message.
"""
from sqlalchemy import Column, Integer, String, Text, ForeignKey, DateTime, func
from sqlalchemy.orm import relationship

from app.core.database import Base


class AICoachConversation(Base):
    __tablename__ = "ai_coach_conversations"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    title = Column(String(150), nullable=False, default="محادثة جديدة")

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    user = relationship("User", foreign_keys=[user_id])
    messages = relationship(
        "AICoachMessage",
        back_populates="conversation",
        cascade="all, delete-orphan",
        order_by="AICoachMessage.created_at",
    )

    def __repr__(self) -> str:
        return f"<AICoachConversation user={self.user_id} title={self.title!r}>"


class AICoachMessage(Base):
    __tablename__ = "ai_coach_messages"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer, ForeignKey("ai_coach_conversations.id", ondelete="CASCADE"), nullable=False, index=True
    )

    # "user" | "assistant" — see app/schemas/ai_coach.py: AICoachMessageRole
    role = Column(String(10), nullable=False, index=True)
    content = Column(Text, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    conversation = relationship("AICoachConversation", back_populates="messages")

    def __repr__(self) -> str:
        return f"<AICoachMessage conv={self.conversation_id} role={self.role}>"
