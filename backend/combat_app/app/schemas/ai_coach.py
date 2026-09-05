import enum
from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, Field


class AICoachMessageRole(str, enum.Enum):
    USER = "user"
    ASSISTANT = "assistant"


# ──────────────────────────────────────────────
#  Conversations
# ──────────────────────────────────────────────

class AICoachConversationCreate(BaseModel):
    title: Optional[str] = Field(None, max_length=150)


class AICoachConversationResponse(BaseModel):
    id: int
    title: str
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


# ──────────────────────────────────────────────
#  Messages
# ──────────────────────────────────────────────

class AICoachMessageResponse(BaseModel):
    id: int
    role: AICoachMessageRole
    content: str
    created_at: datetime

    model_config = {"from_attributes": True}


class AICoachConversationDetailResponse(AICoachConversationResponse):
    messages: List[AICoachMessageResponse] = []


# ──────────────────────────────────────────────
#  Chat (send a message, get a reply)
# ──────────────────────────────────────────────

class AICoachChatRequest(BaseModel):
    # If omitted, a new conversation is created automatically.
    conversation_id: Optional[int] = None
    message: str = Field(..., min_length=1, max_length=4000)


class AICoachChatResponse(BaseModel):
    conversation_id: int
    conversation_title: str
    user_message: AICoachMessageResponse
    assistant_message: AICoachMessageResponse
