from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
from app.schemas.user import UserPublicResponse


class MessageCreate(BaseModel):
    content: Optional[str] = Field(None, max_length=2000)
    media_url: Optional[str] = None
    media_type: Optional[str] = Field(None, pattern="^(image|video)$")

    def model_post_init(self, __context):
        if not self.content and not self.media_url:
            raise ValueError("Message must have content or media")


class MessageResponse(BaseModel):
    id: int
    conversation_id: int
    sender: UserPublicResponse
    content: Optional[str]
    media_url: Optional[str]
    media_type: Optional[str]
    is_read: bool
    deleted_at: Optional[datetime]
    created_at: datetime

    model_config = {"from_attributes": True}

    @property
    def display_content(self) -> str:
        """Returns placeholder if message was soft-deleted."""
        if self.deleted_at:
            return "🚫 This message was deleted"
        return self.content or ""


class ConversationResponse(BaseModel):
    id: int
    other_user: UserPublicResponse
    last_message: Optional[MessageResponse]
    unread_count: int = 0
    last_message_at: datetime

    model_config = {"from_attributes": True}


# ──────────────────────────────────────────────
#  WebSocket Payloads
# ──────────────────────────────────────────────

class WSOutgoingMessage(BaseModel):
    """Shape of JSON sent over WebSocket to the client."""
    event: str                          # "new_message" | "message_read" | "user_typing" | "error"
    data: dict


class WSIncomingMessage(BaseModel):
    """Shape of JSON received from client over WebSocket."""
    type: str                           # "send_message" | "mark_read" | "typing"
    conversation_id: Optional[int] = None
    content: Optional[str] = None
    media_url: Optional[str] = None
    media_type: Optional[str] = None
    message_id: Optional[int] = None   # for mark_read
