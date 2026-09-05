from typing import List, Optional

from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.ai_coach import AICoachConversation, AICoachMessage
from app.repositories.base_repository import BaseRepository


class AICoachRepository(BaseRepository[AICoachConversation]):

    def __init__(self, db: AsyncSession):
        super().__init__(AICoachConversation, db)

    async def create_conversation(self, user_id: int, title: Optional[str] = None) -> AICoachConversation:
        conversation = AICoachConversation(user_id=user_id, title=title or "محادثة جديدة")
        self.db.add(conversation)
        await self.db.flush()
        await self.db.refresh(conversation)
        return conversation

    async def get_with_messages(self, conversation_id: int) -> Optional[AICoachConversation]:
        result = await self.db.execute(
            select(AICoachConversation)
            .options(selectinload(AICoachConversation.messages))
            .where(AICoachConversation.id == conversation_id)
        )
        return result.scalar_one_or_none()

    async def get_user_conversations(
        self, user_id: int, skip: int = 0, limit: int = 20
    ) -> List[AICoachConversation]:
        result = await self.db.execute(
            select(AICoachConversation)
            .where(AICoachConversation.user_id == user_id)
            .order_by(AICoachConversation.updated_at.desc().nulls_last(), desc(AICoachConversation.created_at))
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())

    async def get_recent_messages(self, conversation_id: int, limit: int = 10) -> List[AICoachMessage]:
        """Most recent `limit` messages, returned oldest-first (ready to
        feed straight into the provider as conversation history)."""
        result = await self.db.execute(
            select(AICoachMessage)
            .where(AICoachMessage.conversation_id == conversation_id)
            .order_by(desc(AICoachMessage.created_at))
            .limit(limit)
        )
        messages = list(result.scalars().all())
        messages.reverse()
        return messages

    async def add_message(self, conversation_id: int, role: str, content: str) -> AICoachMessage:
        message = AICoachMessage(conversation_id=conversation_id, role=role, content=content)
        self.db.add(message)
        await self.db.flush()
        await self.db.refresh(message)
        # Bump updated_at on the parent conversation so the list view sorts
        # by most-recently-active first.
        await self.db.execute(
            AICoachConversation.__table__.update()
            .where(AICoachConversation.id == conversation_id)
            .values(updated_at=message.created_at)
        )
        return message
