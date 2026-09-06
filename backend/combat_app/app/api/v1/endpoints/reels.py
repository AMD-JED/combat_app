"""
Reels Endpoints (v9)
======================
POST   /reels/                  ← create (anyone; coach badge is derived, not enforced)
GET    /reels/feed?sport_id=    ← feed filtered by sport (v9 decision, not following-based)
GET    /reels/{id}              ← get one (increments view_count)
DELETE /reels/{id}              ← delete (author only)
POST   /reels/{id}/like         ← toggle simple like/unlike
POST   /reels/{id}/comments     ← add a comment (shares Comment model with Posts — v9 decision)
GET    /reels/{id}/comments     ← list comments
"""
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.models.reel import Reel
from app.repositories.reel_repository import ReelRepository
from app.schemas.reel import ReelCreate, ReelResponse
from app.schemas.post import CommentCreate, CommentResponse

router = APIRouter(prefix="/reels", tags=["Reels"])


def _serialize_reel(
    reel: Reel,
    current_user_id: int,
    likes: Optional[List] = None,
    comments_count: Optional[int] = None,
) -> ReelResponse:
    """
    `likes`/`comments_count` are accepted explicitly (never read off
    `reel.likes`/`reel.comments` when not passed) — mirrors
    posts.py:_serialize_post's same convention: a brand-new reel can't
    have either yet, and touching an unloaded relationship attribute
    here risks an async MissingGreenlet error, since SQLAlchemy may need
    to lazy-load the existing collection first to reconcile
    back_populates bookkeeping.
    """
    likes = reel.likes if likes is None else likes
    count = len(reel.comments) if comments_count is None else comments_count
    user_liked = any(l.user_id == current_user_id for l in likes)
    return ReelResponse(
        id=reel.id,
        author=reel.author,
        media_url=reel.media_url,
        thumbnail_url=reel.thumbnail_url,
        caption=reel.caption,
        sport_id=reel.sport_id,
        duration_seconds=reel.duration_seconds,
        view_count=reel.view_count,
        likes_count=len(likes),
        comments_count=count,
        is_liked_by_me=user_liked,
        is_coach_content=bool(reel.author.is_coach),
        created_at=reel.created_at,
        updated_at=reel.updated_at,
    )


@router.post("/", response_model=ReelResponse, status_code=status.HTTP_201_CREATED)
async def create_reel(
    payload: ReelCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """Anyone can post a Reel — coach authorship is only a badge derived
    from author.is_coach at response time, not a posting restriction
    (confirmed v9 decision)."""
    reel = Reel(
        author_id=current_user.id,
        media_url=payload.media_url,
        thumbnail_url=payload.thumbnail_url,
        caption=payload.caption,
        sport_id=payload.sport_id,
        duration_seconds=payload.duration_seconds,
    )
    repo = ReelRepository(db)
    created = await repo.create(reel)
    await db.commit()
    created.author = current_user
    return _serialize_reel(created, current_user.id, likes=[], comments_count=0)


@router.get("/feed", response_model=List[ReelResponse])
async def get_reels_feed(
    sport_id: Optional[int] = None,
    skip: int = 0,
    limit: int = 20,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = ReelRepository(db)
    reels = await repo.get_feed(sport_id=sport_id, skip=skip, limit=limit)
    return [_serialize_reel(r, current_user.id) for r in reels]


@router.get("/{reel_id}", response_model=ReelResponse)
async def get_reel(
    reel_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = ReelRepository(db)
    reel = await repo.get_with_relations(reel_id)
    if not reel:
        raise HTTPException(status_code=404, detail="Reel not found")

    await repo.increment_view(reel_id)
    await db.commit()

    reel = await repo.get_with_relations(reel_id)
    return _serialize_reel(reel, current_user.id)


@router.delete("/{reel_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_reel(
    reel_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = ReelRepository(db)
    reel = await repo.get_by_id(reel_id)
    if not reel:
        raise HTTPException(status_code=404, detail="Reel not found")
    if reel.author_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")
    await repo.delete_reel(reel_id)
    await db.commit()


@router.post("/{reel_id}/like")
async def toggle_reel_like(
    reel_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = ReelRepository(db)
    reel = await repo.get_by_id(reel_id)
    if not reel:
        raise HTTPException(status_code=404, detail="Reel not found")

    action = await repo.toggle_like(reel_id, current_user.id)
    await db.commit()
    return {"action": action, "reel_id": reel_id}


@router.post("/{reel_id}/comments", response_model=CommentResponse, status_code=status.HTTP_201_CREATED)
async def add_reel_comment(
    reel_id: int,
    payload: CommentCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = ReelRepository(db)
    reel = await repo.get_by_id(reel_id)
    if not reel:
        raise HTTPException(status_code=404, detail="Reel not found")

    comment = await repo.add_comment(reel_id, current_user.id, payload.content)
    await db.commit()
    await db.refresh(comment)
    comment.author = current_user
    return comment


@router.get("/{reel_id}/comments", response_model=List[CommentResponse])
async def get_reel_comments(
    reel_id: int,
    skip: int = 0,
    limit: int = 50,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = ReelRepository(db)
    reel = await repo.get_by_id(reel_id)
    if not reel:
        raise HTTPException(status_code=404, detail="Reel not found")

    comments = await repo.get_comments(reel_id, skip=skip, limit=limit)
    return comments
