from urllib.parse import urlparse

from pydantic import BaseModel, Field, model_validator
from typing import Optional, List
from datetime import datetime
from app.schemas.user import UserPublicResponse


ALLOWED_MEDIA_HOSTS = {"res.cloudinary.com"}


def is_allowed_media_url(url: str) -> bool:
    """A message attachment must be an https URL on our media CDN.

    The client uploads through /uploads/message/* first and then sends the
    returned URL; without this check any client could make the app load an
    arbitrary third-party URL inside every recipient's chat."""
    try:
        parsed = urlparse(url)
    except ValueError:
        return False
    return parsed.scheme == "https" and parsed.hostname in ALLOWED_MEDIA_HOSTS


def validate_message_payload(content, media_url, media_type) -> None:
    """Shared by REST (MessageCreate) and WebSocket handling. Raises ValueError."""
    if not content and not media_url:
        raise ValueError("Message must have content or media")
    if media_url:
        if media_type not in ("image", "video"):
            raise ValueError("media_type (image|video) is required with media_url")
        if not is_allowed_media_url(media_url):
            raise ValueError("media_url must be an https Cloudinary URL")
    elif media_type:
        raise ValueError("media_type given without media_url")


class MessageCreate(BaseModel):
    content: Optional[str] = Field(None, max_length=2000)
    media_url: Optional[str] = Field(None, max_length=1000)
    media_type: Optional[str] = Field(None, pattern="^(image|video)$")

    @model_validator(mode="after")
    def _check_payload(self):
        validate_message_payload(self.content, self.media_url, self.media_type)
        return self


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
    # Set when this message is a reply to someone's story (POST /stories/{id}/reply)
    reply_to_story_id: Optional[int] = None

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
    other_user_online: bool = False

    model_config = {"from_attributes": True}


# ──────────────────────────────────────────────
#  WebSocket Payloads
# ──────────────────────────────────────────────

class WSOutgoingMessage(BaseModel):
    """Shape of JSON sent over WebSocket to the client."""
    event: str                          # "new_message" | "message_read" | "user_typing" | "presence" | "error"
    data: dict


class WSIncomingMessage(BaseModel):
    """Shape of JSON received from client over WebSocket."""
    type: str                           # "send_message" | "mark_read" | "typing"
    conversation_id: Optional[int] = None
    content: Optional[str] = None
    media_url: Optional[str] = None
    media_type: Optional[str] = None
    message_id: Optional[int] = None   # for mark_read
