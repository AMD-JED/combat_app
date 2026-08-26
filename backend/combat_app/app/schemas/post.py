from pydantic import BaseModel, Field
from typing import Optional, Dict
from datetime import datetime
from app.models.post import PostType, ReactionType
from app.schemas.user import UserPublicResponse

# All 6 reaction types, always present in PostResponse.reaction_counts (0 if
# unused) so frontend code can index them directly without None-checks —
# mirrors `Post.reactionCounts` in the React prototype's src/types.ts.
ZERO_REACTION_COUNTS: Dict[str, int] = {rt.value: 0 for rt in ReactionType}


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


class ReactionCreate(BaseModel):
    """POST /posts/{post_id}/react body. One of the 6 Athletes Hub reaction
    types (see ReactionType). Sending the same type the user already has
    toggles it off — see PostRepository.react_to_post."""
    reaction_type: ReactionType


class PostResponse(BaseModel):
    id: int
    content: Optional[str]
    media_url: Optional[str]
    post_type: PostType
    tags: Optional[str]
    author: UserPublicResponse
    likes_count: int = 0  # kept for backward compat = total reactions of any type
    comments_count: int = 0
    # v5 additions — rich reactions (see app/models/post.py:ReactionType)
    reaction_counts: Dict[str, int] = Field(default_factory=lambda: dict(ZERO_REACTION_COUNTS))
    user_reaction: Optional[ReactionType] = None
    is_liked_by_me: bool = False  # convenience = (user_reaction is not None)
    created_at: datetime

    model_config = {"from_attributes": True}
