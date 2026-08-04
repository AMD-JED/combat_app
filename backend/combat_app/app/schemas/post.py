from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
from app.models.post import PostType
from app.schemas.user import UserPublicResponse


class PostCreate(BaseModel):
    content: Optional[str] = Field(None, max_length=2000)
    post_type: PostType = PostType.TEXT
    tags: Optional[str] = Field(None, max_length=500)

    @property
    def validate_content(self):
        if not self.content and not self.media_url:
            raise ValueError("Post must have content or media")


class PostUpdate(BaseModel):
    content: Optional[str] = Field(None, max_length=2000)
    tags: Optional[str] = Field(None, max_length=500)


class CommentCreate(BaseModel):
    content: str = Field(..., min_length=1, max_length=500)


class CommentResponse(BaseModel):
    id: int
    content: str
    author: UserPublicResponse
    created_at: datetime

    model_config = {"from_attributes": True}


class PostResponse(BaseModel):
    id: int
    content: Optional[str]
    media_url: Optional[str]
    post_type: PostType
    tags: Optional[str]
    author: UserPublicResponse
    likes_count: int = 0
    comments_count: int = 0
    created_at: datetime

    model_config = {"from_attributes": True}
