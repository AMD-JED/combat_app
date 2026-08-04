"""
Messaging Endpoints
===================

REST (for history & management):
  GET  /messages/conversations          ← list all my conversations
  POST /messages/conversations/{user_id}← start or open a DM
  GET  /messages/conversations/{id}/messages ← paginated history
  POST /messages/conversations/{id}/read     ← mark as read
  DELETE /messages/{message_id}              ← soft-delete a message

WebSocket (for real-time):
  WS /messages/ws?token=<JWT>

  Client sends JSON:
    { "type": "send_message", "conversation_id": 5, "content": "yo!" }
    { "type": "mark_read",    "conversation_id": 5 }
    { "type": "typing",       "conversation_id": 5 }

  Server pushes JSON:
    { "event": "new_message",  "data": { ...MessageResponse } }
    { "event": "message_read", "data": { "conversation_id": 5 } }
    { "event": "user_typing",  "data": { "user_id": 3, "conversation_id": 5 } }
    { "event": "error",        "data": { "detail": "..." } }
"""

import json
from typing import List

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import decode_token
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.repositories.message_repository import ConversationRepository, MessageRepository
from app.schemas.message import (
    MessageCreate, MessageResponse, ConversationResponse, WSIncomingMessage
)
from app.services.connection_manager import manager

router = APIRouter(prefix="/messages", tags=["Direct Messages"])


# ──────────────────────────────────────────────
#  Helper
# ──────────────────────────────────────────────

def _msg_to_dict(msg, sender) -> dict:
    return {
        "id": msg.id,
        "conversation_id": msg.conversation_id,
        "sender": {
            "id": sender.id,
            "username": sender.username,
            "full_name": sender.full_name,
            "avatar_url": sender.avatar_url,
        },
        "content": None if msg.deleted_at else msg.content,
        "media_url": None if msg.deleted_at else msg.media_url,
        "media_type": msg.media_type,
        "is_read": msg.is_read,
        "deleted_at": msg.deleted_at.isoformat() if msg.deleted_at else None,
        "created_at": msg.created_at.isoformat(),
    }


# ──────────────────────────────────────────────
#  REST Endpoints
# ──────────────────────────────────────────────

@router.get("/conversations", response_model=List[ConversationResponse])
async def list_conversations(
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """List all DM conversations for the current user, newest first."""
    conv_repo = ConversationRepository(db)
    msg_repo = MessageRepository(db)
    conversations = await conv_repo.get_user_conversations(current_user.id)

    result = []
    for conv in conversations:
        other = conv.other_user(current_user.id)
        msgs = await msg_repo.get_conversation_messages(conv.id, limit=1)
        unread = await msg_repo.unread_count(conv.id, current_user.id)
        result.append(
            ConversationResponse(
                id=conv.id,
                other_user=other,
                last_message=MessageResponse.model_validate(msgs[0]) if msgs else None,
                unread_count=unread,
                last_message_at=conv.last_message_at,
            )
        )
    return result


@router.post("/conversations/{user_id}", status_code=status.HTTP_200_OK)
async def open_conversation(
    user_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """Open (or create) a DM conversation with another user."""
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot message yourself")

    user_repo = UserRepository(db)
    target = await user_repo.get_by_id(user_id)
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    conv_repo = ConversationRepository(db)
    conv, created = await conv_repo.get_or_create(current_user.id, user_id)
    return {"conversation_id": conv.id, "created": created}


@router.get("/conversations/{conversation_id}/messages", response_model=List[MessageResponse])
async def get_messages(
    conversation_id: int,
    skip: int = 0,
    limit: int = 50,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """Get paginated message history for a conversation."""
    conv_repo = ConversationRepository(db)
    if not await conv_repo.user_belongs_to(current_user.id, conversation_id):
        raise HTTPException(status_code=403, detail="Not a participant of this conversation")

    msg_repo = MessageRepository(db)
    messages = await msg_repo.get_conversation_messages(conversation_id, skip=skip, limit=limit)
    return [MessageResponse.model_validate(m) for m in messages]


@router.post(
    "/conversations/{conversation_id}/messages",
    response_model=MessageResponse,
    status_code=status.HTTP_201_CREATED,
)
async def send_message_rest(
    conversation_id: int,
    message_data: MessageCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Send a message via REST (fallback for clients not using WebSocket).
    Mirrors the 'send_message' WebSocket event logic.
    """
    conv_repo = ConversationRepository(db)
    if not await conv_repo.user_belongs_to(current_user.id, conversation_id):
        raise HTTPException(status_code=403, detail="Not a participant of this conversation")

    msg_repo = MessageRepository(db)
    msg = await msg_repo.send(
        conversation_id=conversation_id,
        sender_id=current_user.id,
        content=message_data.content,
        media_url=message_data.media_url,
        media_type=message_data.media_type,
    )
    await db.commit()

    # Reload with sender relationship for response_model serialization
    await db.refresh(msg, attribute_names=["sender"])
    return MessageResponse.model_validate(msg)


@router.post("/conversations/{conversation_id}/read")
async def mark_read(
    conversation_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """Mark all unread messages in a conversation as read."""
    conv_repo = ConversationRepository(db)
    if not await conv_repo.user_belongs_to(current_user.id, conversation_id):
        raise HTTPException(status_code=403, detail="Not a participant")

    msg_repo = MessageRepository(db)
    count = await msg_repo.mark_read(conversation_id, current_user.id)
    return {"marked_read": count}


@router.delete("/{message_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_message(
    message_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """Soft-delete a message (only sender can delete)."""
    msg_repo = MessageRepository(db)
    deleted = await msg_repo.soft_delete(message_id, current_user.id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Message not found or already deleted")


# ──────────────────────────────────────────────
#  WebSocket Endpoint
# ──────────────────────────────────────────────

@router.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket,
    token: str = Query(..., description="JWT access token"),
    db: AsyncSession = Depends(get_db),
):
    """
    Real-time WebSocket connection.

    Authenticate via ?token=<JWT> query param.
    After connecting, send/receive JSON messages.

    Incoming message types:
      send_message  → send a message to a conversation
      mark_read     → mark conversation as read
      typing        → notify the other user you're typing
    """
    # ── Authenticate ──
    payload = decode_token(token)
    if not payload or payload.get("type") != "access":
        await websocket.close(code=4001, reason="Invalid token")
        return

    user_repo = UserRepository(db)
    current_user = await user_repo.get_by_id(int(payload["sub"]))
    if not current_user or not current_user.is_active:
        await websocket.close(code=4001, reason="User not found")
        return

    # ── Connect ──
    await manager.connect(current_user.id, websocket)

    # Send presence confirmation
    await websocket.send_json({
        "event": "connected",
        "data": {"user_id": current_user.id, "message": "Connected to Combat Sports Messenger 🥊"}
    })

    conv_repo = ConversationRepository(db)
    msg_repo = MessageRepository(db)

    try:
        while True:
            raw = await websocket.receive_text()

            try:
                incoming = WSIncomingMessage.model_validate_json(raw)
            except Exception:
                await websocket.send_json({"event": "error", "data": {"detail": "Invalid JSON payload"}})
                continue

            # ── send_message ──
            if incoming.type == "send_message":
                if not incoming.conversation_id:
                    await websocket.send_json({"event": "error", "data": {"detail": "conversation_id required"}})
                    continue

                if not await conv_repo.user_belongs_to(current_user.id, incoming.conversation_id):
                    await websocket.send_json({"event": "error", "data": {"detail": "Not a participant"}})
                    continue

                msg = await msg_repo.send(
                    conversation_id=incoming.conversation_id,
                    sender_id=current_user.id,
                    content=incoming.content,
                    media_url=incoming.media_url,
                    media_type=incoming.media_type,
                )
                await db.commit()

                msg_dict = _msg_to_dict(msg, current_user)
                push = {"event": "new_message", "data": msg_dict}

                # Deliver to sender (all their devices)
                await manager.send_to_user(current_user.id, push)

                # Deliver to the other user
                conv = await conv_repo.get_by_id(incoming.conversation_id)
                other_id = conv.user_2_id if conv.user_1_id == current_user.id else conv.user_1_id
                await manager.send_to_user(other_id, push)

            # ── mark_read ──
            elif incoming.type == "mark_read":
                if not incoming.conversation_id:
                    continue
                count = await msg_repo.mark_read(incoming.conversation_id, current_user.id)
                await db.commit()

                if count > 0:
                    conv = await conv_repo.get_by_id(incoming.conversation_id)
                    other_id = conv.user_2_id if conv.user_1_id == current_user.id else conv.user_1_id
                    await manager.send_to_user(other_id, {
                        "event": "message_read",
                        "data": {"conversation_id": incoming.conversation_id, "read_by": current_user.id}
                    })

            # ── typing indicator ──
            elif incoming.type == "typing":
                if not incoming.conversation_id:
                    continue
                conv = await conv_repo.get_by_id(incoming.conversation_id)
                if not conv:
                    continue
                other_id = conv.user_2_id if conv.user_1_id == current_user.id else conv.user_1_id
                await manager.send_to_user(other_id, {
                    "event": "user_typing",
                    "data": {
                        "user_id": current_user.id,
                        "username": current_user.username,
                        "conversation_id": incoming.conversation_id,
                    }
                })

            else:
                await websocket.send_json({"event": "error", "data": {"detail": f"Unknown type: {incoming.type}"}})

    except WebSocketDisconnect:
        manager.disconnect(current_user.id, websocket)
