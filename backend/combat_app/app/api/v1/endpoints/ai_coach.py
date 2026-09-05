from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.repositories.ai_coach_repository import AICoachRepository
from app.schemas.ai_coach import (
    AICoachChatRequest,
    AICoachChatResponse,
    AICoachConversationDetailResponse,
    AICoachConversationResponse,
)
from app.services import gemini_service
from app.services.coach_context_service import build_user_context

router = APIRouter(prefix="/ai-coach", tags=["AI Coach"])


@router.post("/chat", response_model=AICoachChatResponse)
async def chat_with_coach(
    payload: AICoachChatRequest,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = AICoachRepository(db)

    if payload.conversation_id is not None:
        conversation = await repo.get_by_id(payload.conversation_id)
        if not conversation:
            raise HTTPException(status_code=404, detail="Conversation not found")
        if conversation.user_id != current_user.id:
            raise HTTPException(status_code=403, detail="Not authorized to use this conversation")
    else:
        auto_title = payload.message.strip()[:50] or "محادثة جديدة"
        conversation = await repo.create_conversation(current_user.id, title=auto_title)

    # Prior turns, before this new message is saved (so it isn't
    # duplicated into the history sent to the provider).
    history_messages = await repo.get_recent_messages(conversation.id, limit=10)
    history = [{"role": m.role, "content": m.content} for m in history_messages]

    user_message = await repo.add_message(conversation.id, role="user", content=payload.message)

    system_context = await build_user_context(current_user, db)

    try:
        reply_text = await gemini_service.generate_coach_reply(
            system_context=system_context,
            history=history,
            user_message=payload.message,
        )
    except RuntimeError as e:
        # Missing/invalid API key etc — surfaced as a clear 503 rather
        # than a generic 500.
        raise HTTPException(status_code=503, detail=str(e))
    except Exception:
        raise HTTPException(status_code=502, detail="AI Coach is temporarily unavailable. Please try again.")

    assistant_message = await repo.add_message(conversation.id, role="assistant", content=reply_text)

    await db.commit()

    return AICoachChatResponse(
        conversation_id=conversation.id,
        conversation_title=conversation.title,
        user_message=user_message,
        assistant_message=assistant_message,
    )


@router.get("/conversations", response_model=List[AICoachConversationResponse])
async def list_conversations(
    skip: int = 0,
    limit: int = 20,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = AICoachRepository(db)
    return await repo.get_user_conversations(current_user.id, skip=skip, limit=limit)


@router.get("/conversations/{conversation_id}", response_model=AICoachConversationDetailResponse)
async def get_conversation(
    conversation_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = AICoachRepository(db)
    conversation = await repo.get_with_messages(conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    if conversation.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized to view this conversation")
    return conversation


@router.delete("/conversations/{conversation_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_conversation(
    conversation_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = AICoachRepository(db)
    conversation = await repo.get_by_id(conversation_id)
    if not conversation:
        raise HTTPException(status_code=404, detail="Conversation not found")
    if conversation.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized to delete this conversation")

    await repo.delete(conversation_id)
    await db.commit()
    return None
