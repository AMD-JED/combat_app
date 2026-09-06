"""
Highlights Endpoints (v9)
==========================
POST   /highlights/                              ← create a collection (optionally with initial stories)
GET    /highlights/user/{user_id}                ← list a user's highlights (profile view)
GET    /highlights/{id}                          ← get one highlight with its pinned stories
POST   /highlights/{id}/stories                  ← pin more stories to it
DELETE /highlights/{id}/stories/{story_id}        ← unpin one story
DELETE /highlights/{id}                          ← delete the whole collection
"""
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.models.story import Highlight
from app.repositories.story_repository import HighlightRepository, StoryRepository
from app.schemas.story import (
    HighlightCreate,
    HighlightAddStories,
    HighlightResponse,
    StoryResponse,
)

router = APIRouter(prefix="/highlights", tags=["Highlights"])


async def _serialize_highlight(highlight: Highlight, story_repo: StoryRepository, viewer_id: int) -> HighlightResponse:
    stories = []
    for item in highlight.items:
        s = item.story
        stories.append(
            StoryResponse(
                id=s.id,
                author=s.author,
                content_type=s.content_type,
                media_url=s.media_url,
                text_content=s.text_content,
                background_color=s.background_color,
                visibility=s.visibility,
                views_count=await story_repo.get_views_count(s.id),
                viewed_by_me=await story_repo.viewed_by(s.id, viewer_id),
                created_at=s.created_at,
                expires_at=s.expires_at,
            )
        )
    cover = highlight.cover_media_url or (stories[0].media_url if stories else None)
    return HighlightResponse(
        id=highlight.id,
        title=highlight.title,
        cover_media_url=cover,
        stories=stories,
        created_at=highlight.created_at,
        updated_at=highlight.updated_at,
    )


@router.post("/", response_model=HighlightResponse, status_code=status.HTTP_201_CREATED)
async def create_highlight(
    payload: HighlightCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = HighlightRepository(db)
    highlight = await repo.create_with_stories(current_user.id, payload.title, payload.story_ids)
    await db.commit()

    highlight = await repo.get_with_stories(highlight.id)
    return await _serialize_highlight(highlight, StoryRepository(db), current_user.id)


@router.get("/user/{user_id}", response_model=List[HighlightResponse])
async def get_user_highlights(
    user_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = HighlightRepository(db)
    highlights = await repo.get_user_highlights(user_id)
    story_repo = StoryRepository(db)
    return [await _serialize_highlight(h, story_repo, current_user.id) for h in highlights]


@router.get("/{highlight_id}", response_model=HighlightResponse)
async def get_highlight(
    highlight_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = HighlightRepository(db)
    highlight = await repo.get_with_stories(highlight_id)
    if not highlight:
        raise HTTPException(status_code=404, detail="Highlight not found")
    return await _serialize_highlight(highlight, StoryRepository(db), current_user.id)


@router.post("/{highlight_id}/stories", response_model=HighlightResponse)
async def add_stories_to_highlight(
    highlight_id: int,
    payload: HighlightAddStories,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = HighlightRepository(db)
    highlight = await repo.get_by_id(highlight_id)
    if not highlight:
        raise HTTPException(status_code=404, detail="Highlight not found")
    if highlight.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")

    await repo.add_stories(highlight_id, payload.story_ids)
    await db.commit()

    highlight = await repo.get_with_stories(highlight_id)
    return await _serialize_highlight(highlight, StoryRepository(db), current_user.id)


@router.delete("/{highlight_id}/stories/{story_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_story_from_highlight(
    highlight_id: int,
    story_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = HighlightRepository(db)
    highlight = await repo.get_by_id(highlight_id)
    if not highlight:
        raise HTTPException(status_code=404, detail="Highlight not found")
    if highlight.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")

    removed = await repo.remove_story(highlight_id, story_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Story not pinned in this highlight")
    await db.commit()


@router.delete("/{highlight_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_highlight(
    highlight_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = HighlightRepository(db)
    highlight = await repo.get_by_id(highlight_id)
    if not highlight:
        raise HTTPException(status_code=404, detail="Highlight not found")
    if highlight.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")

    await repo.delete_highlight(highlight_id)
    await db.commit()
