"""
Stories Endpoints (v9)
=======================
POST   /stories/                     ← create (image/video/text, expires in 24h)
GET    /stories/feed                 ← active stories from me + people I follow
GET    /stories/{id}                 ← get one active story (records a view)
GET    /stories/{id}/views           ← "seen by" list (author only)
DELETE /stories/{id}                 ← delete (also removes it from any Highlights)
POST   /stories/{id}/reply           ← reply via DM to the story's author
"""
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.models.story import Story
from app.repositories.story_repository import StoryRepository
from app.repositories.user_repository import UserRepository
from app.repositories.message_repository import ConversationRepository, MessageRepository
from app.services import notification_service
from app.schemas.story import (
    StoryCreate,
    StoryResponse,
    StoryViewerResponse,
    StoryReplyCreate,
)

router = APIRouter(prefix="/stories", tags=["Stories"])


async def _serialize_story(story: Story, repo: StoryRepository, current_user_id: int) -> StoryResponse:
    views_count = await repo.get_views_count(story.id)
    viewed_by_me = await repo.viewed_by(story.id, current_user_id)
    return StoryResponse(
        id=story.id,
        author=story.author,
        content_type=story.content_type,
        media_url=story.media_url,
        text_content=story.text_content,
        background_color=story.background_color,
        visibility=story.visibility,
        views_count=views_count,
        viewed_by_me=viewed_by_me,
        created_at=story.created_at,
        expires_at=story.expires_at,
    )


@router.post("/", response_model=StoryResponse, status_code=status.HTTP_201_CREATED)
async def create_story(
    payload: StoryCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = StoryRepository(db)
    story = await repo.create_story(
        author_id=current_user.id,
        content_type=payload.content_type.value,
        media_url=payload.media_url,
        text_content=payload.text_content,
        background_color=payload.background_color,
        visibility=payload.visibility.value,
    )
    await db.commit()
    story.author = current_user
    return await _serialize_story(story, repo, current_user.id)


@router.get("/feed", response_model=List[StoryResponse])
async def get_stories_feed(
    skip: int = 0,
    limit: int = 50,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """Active (not expired) stories from the current user plus everyone
    they follow, respecting each story's own public/followers visibility."""
    user_repo = UserRepository(db)
    user = await user_repo.get_with_relations(current_user.id)
    following_ids = [u.id for u in user.following]

    repo = StoryRepository(db)
    stories = await repo.get_active_feed(current_user.id, following_ids, skip=skip, limit=limit)
    return [await _serialize_story(s, repo, current_user.id) for s in stories]


@router.get("/{story_id}", response_model=StoryResponse)
async def get_story(
    story_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = StoryRepository(db)
    story = await repo.get_active_by_id(story_id)
    if not story:
        raise HTTPException(status_code=404, detail="Story not found or has expired")

    if story.visibility == "followers" and story.author_id != current_user.id:
        user_repo = UserRepository(db)
        user = await user_repo.get_with_relations(current_user.id)
        following_ids = {u.id for u in user.following}
        if story.author_id not in following_ids:
            raise HTTPException(status_code=403, detail="This story is only visible to the author's followers")

    if story.author_id != current_user.id:
        await repo.record_view(story_id, current_user.id)
        await db.commit()

    return await _serialize_story(story, repo, current_user.id)


@router.get("/{story_id}/views", response_model=List[StoryViewerResponse])
async def get_story_views(
    story_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """'Seen by' list — only the story's author can see who viewed it."""
    repo = StoryRepository(db)
    story = await repo.get_by_id(story_id)  # allow author to check even if expired
    if not story:
        raise HTTPException(status_code=404, detail="Story not found")
    if story.author_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the author can view this list")

    viewers = await repo.get_viewers(story_id)
    return [StoryViewerResponse(viewer=v.viewer, viewed_at=v.viewed_at) for v in viewers]


@router.delete("/{story_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_story(
    story_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """Deleting a story also removes it from any Highlights it was pinned
    to (ondelete=CASCADE on HighlightStory.story_id — confirmed decision)."""
    repo = StoryRepository(db)
    story = await repo.get_by_id(story_id)
    if not story:
        raise HTTPException(status_code=404, detail="Story not found")
    if story.author_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")
    await repo.delete_story(story_id)
    await db.commit()


@router.post("/{story_id}/reply", status_code=status.HTTP_201_CREATED)
async def reply_to_story(
    story_id: int,
    payload: StoryReplyCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """Sends a DM to the story's author, tagged with reply_to_story_id.
    Opens (or reuses) the existing 1:1 conversation between the two users."""
    story_repo = StoryRepository(db)
    story = await story_repo.get_active_by_id(story_id)
    if not story:
        raise HTTPException(status_code=404, detail="Story not found or has expired")
    if story.author_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot reply to your own story")

    conv_repo = ConversationRepository(db)
    conv, _ = await conv_repo.get_or_create(current_user.id, story.author_id)

    msg_repo = MessageRepository(db)
    msg = await msg_repo.send(conversation_id=conv.id, sender_id=current_user.id, content=payload.content)
    msg.reply_to_story_id = story_id
    await db.commit()
    await db.refresh(msg, attribute_names=["sender"])

    await notification_service.create_and_push(
        db,
        recipient_id=story.author_id,
        type="message",
        title=f"New message from {current_user.username}",
        body=payload.content[:200],
        actor_id=current_user.id,
        data={"conversation_id": conv.id, "message_id": msg.id, "reply_to_story_id": story_id},
    )
    await db.commit()

    return {
        "conversation_id": conv.id,
        "message_id": msg.id,
        "reply_to_story_id": story_id,
    }
