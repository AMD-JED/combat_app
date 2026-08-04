from typing import Optional, List
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, func, update
from sqlalchemy.orm import selectinload

from app.models.message import Conversation, Message
from app.repositories.base_repository import BaseRepository


class ConversationRepository(BaseRepository[Conversation]):

    def __init__(self, db: AsyncSession):
        super().__init__(Conversation, db)

    async def get_or_create(self, user_a: int, user_b: int) -> tuple[Conversation, bool]:
        """
        Get existing conversation or create a new one.
        Always stores lower user ID as user_1 to avoid duplicates.
        Returns (conversation, created: bool)
        """
        lo, hi = sorted([user_a, user_b])

        result = await self.db.execute(
            select(Conversation)
            .options(
                selectinload(Conversation.user_1),
                selectinload(Conversation.user_2),
            )
            .where(
                and_(Conversation.user_1_id == lo, Conversation.user_2_id == hi)
            )
        )
        conv = result.scalar_one_or_none()
        if conv:
            return conv, False

        conv = Conversation(user_1_id=lo, user_2_id=hi)
        self.db.add(conv)
        await self.db.flush()
        await self.db.refresh(conv)
        return conv, True

    async def get_user_conversations(self, user_id: int) -> List[Conversation]:
        """Get all conversations for a user, newest activity first."""
        result = await self.db.execute(
            select(Conversation)
            .options(
                selectinload(Conversation.user_1),
                selectinload(Conversation.user_2),
                selectinload(Conversation.messages).selectinload(Message.sender),
            )
            .where(
                or_(
                    Conversation.user_1_id == user_id,
                    Conversation.user_2_id == user_id,
                )
            )
            .order_by(Conversation.last_message_at.desc())
        )
        return list(result.scalars().all())

    async def get_with_messages(self, conversation_id: int, skip: int = 0, limit: int = 50) -> Optional[Conversation]:
        result = await self.db.execute(
            select(Conversation)
            .options(
                selectinload(Conversation.user_1),
                selectinload(Conversation.user_2),
            )
            .where(Conversation.id == conversation_id)
        )
        return result.scalar_one_or_none()

    async def user_belongs_to(self, user_id: int, conversation_id: int) -> bool:
        result = await self.db.execute(
            select(Conversation.id).where(
                and_(
                    Conversation.id == conversation_id,
                    or_(
                        Conversation.user_1_id == user_id,
                        Conversation.user_2_id == user_id,
                    ),
                )
            )
        )
        return result.scalar_one_or_none() is not None


class MessageRepository(BaseRepository[Message]):

    def __init__(self, db: AsyncSession):
        super().__init__(Message, db)

    async def get_conversation_messages(
        self, conversation_id: int, skip: int = 0, limit: int = 50
    ) -> List[Message]:
        result = await self.db.execute(
            select(Message)
            .options(selectinload(Message.sender))
            .where(Message.conversation_id == conversation_id)
            .order_by(Message.created_at.desc())   # newest first, client reverses
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())

    async def send(
        self,
        conversation_id: int,
        sender_id: int,
        content: Optional[str] = None,
        media_url: Optional[str] = None,
        media_type: Optional[str] = None,
    ) -> Message:
        msg = Message(
            conversation_id=conversation_id,
            sender_id=sender_id,
            content=content,
            media_url=media_url,
            media_type=media_type,
        )
        self.db.add(msg)

        # Bump conversation's last_message_at
        await self.db.execute(
            update(Conversation)
            .where(Conversation.id == conversation_id)
            .values(last_message_at=func.now())
        )
        await self.db.flush()
        await self.db.refresh(msg)
        return msg

    async def mark_read(self, conversation_id: int, reader_id: int) -> int:
        """Mark all unread messages (not sent by reader) as read. Returns count."""
        result = await self.db.execute(
            update(Message)
            .where(
                and_(
                    Message.conversation_id == conversation_id,
                    Message.sender_id != reader_id,
                    Message.is_read == False,
                )
            )
            .values(is_read=True)
        )
        return result.rowcount

    async def soft_delete(self, message_id: int, user_id: int) -> bool:
        """Only the sender can delete their own message."""
        from datetime import datetime, timezone
        result = await self.db.execute(
            update(Message)
            .where(
                and_(
                    Message.id == message_id,
                    Message.sender_id == user_id,
                    Message.deleted_at.is_(None),
                )
            )
            .values(deleted_at=datetime.now(timezone.utc))
        )
        return result.rowcount > 0

    async def unread_count(self, conversation_id: int, user_id: int) -> int:
        result = await self.db.execute(
            select(func.count()).select_from(Message).where(
                and_(
                    Message.conversation_id == conversation_id,
                    Message.sender_id != user_id,
                    Message.is_read == False,
                    Message.deleted_at.is_(None),
                )
            )
        )
        return result.scalar_one()
