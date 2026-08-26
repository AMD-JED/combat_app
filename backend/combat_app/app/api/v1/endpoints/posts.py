from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.models.post import Post, PostReaction, ReactionType
from app.repositories.post_repository import PostRepository
from app.repositories.user_repository import UserRepository
from app.schemas.post import (
    PostCreate,
    PostResponse,
    CommentCreate,
    CommentResponse,
    ReactionCreate,
    ZERO_REACTION_COUNTS,
)

router = APIRouter(prefix="/posts", tags=["Posts"])


def _serialize_post(
    post: Post, current_user_id: int, reactions: List[PostReaction], comments_count: int
) -> PostResponse:
    """
    Single place that turns a `Post` ORM object + its reactions into a
    `PostResponse`. Both `reactions` and `comments_count` are passed
    explicitly (never read off `post.reactions`/`post.comments` inside this
    function) so callers control exactly what's loaded:
      - get_feed / get_user_posts: pass the selectinload'ed `p.reactions`
        and `len(p.comments)` — safe, both were eagerly loaded by the repo.
      - create_post: pass `reactions=[]`, `comments_count=0` — a brand-new
        post can't have either yet, and touching an unloaded relationship
        attribute here (even just to assign `[]`) risks an async
        MissingGreenlet error, since SQLAlchemy may need to lazy-load the
        existing collection first to reconcile back_populates bookkeeping.
    """
    counts = dict(ZERO_REACTION_COUNTS)
    user_reaction: ReactionType | None = None
    for r in reactions:
        counts[r.reaction_type] = counts.get(r.reaction_type, 0) + 1
        if r.user_id == current_user_id:
            user_reaction = ReactionType(r.reaction_type)

    return PostResponse(
        id=post.id,
        content=post.content,
        media_url=post.media_url,
        post_type=post.post_type,
        tags=post.tags,
        author=post.author,
        likes_count=len(reactions),
        comments_count=comments_count,
        reaction_counts=counts,
        user_reaction=user_reaction,
        is_liked_by_me=user_reaction is not None,
        created_at=post.created_at,
    )


@router.get("/feed", response_model=List[PostResponse])
async def get_feed(
    skip: int = 0,
    limit: int = 20,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    user_repo = UserRepository(db)
    user = await user_repo.get_with_relations(current_user.id)
    following_ids = [u.id for u in user.following] + [current_user.id]

    post_repo = PostRepository(db)
    posts = await post_repo.get_feed(following_ids, skip=skip, limit=limit)

    return [
        _serialize_post(p, current_user.id, p.reactions, len(p.comments))
        for p in posts
    ]


@router.post("/", response_model=PostResponse, status_code=status.HTTP_201_CREATED)
async def create_post(
    payload: PostCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    post = Post(
        author_id=current_user.id,
        content=payload.content,
        post_type=payload.post_type,
        tags=payload.tags,
    )
    repo = PostRepository(db)
    created = await repo.create(post)
    await db.commit()
    await db.refresh(created)
    created.author = current_user
    return _serialize_post(created, current_user.id, reactions=[], comments_count=0)


@router.delete("/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_post(
    post_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = PostRepository(db)
    post = await repo.get_by_id(post_id)
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    if post.author_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")
    await repo.delete(post_id)
    await db.commit()


@router.post("/{post_id}/react")
async def react_to_post(
    post_id: int,
    payload: ReactionCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """
    v5 — Athletes Hub rich reactions. Sending the same reaction_type the
    user already has on this post removes it (toggle off); sending a
    different type switches it. Lightweight response by design (matches
    the existing /like convention) — the client applies the optimistic
    update locally rather than re-fetching the full post.
    """
    repo = PostRepository(db)
    post = await repo.get_by_id(post_id)
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    action = await repo.react_to_post(current_user.id, post_id, payload.reaction_type)
    await db.commit()
    return {"action": action, "post_id": post_id, "reaction_type": payload.reaction_type.value}


@router.post("/{post_id}/like")
async def toggle_like(
    post_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Legacy endpoint kept for the existing Flutter client — always toggles
    the 'fire' reaction under the hood so old and new clients read/write
    the same underlying `post_reactions` table (single source of truth,
    no separate like-count to drift out of sync). New clients should
    prefer POST /{post_id}/react with an explicit reaction_type.
    """
    repo = PostRepository(db)
    post = await repo.get_by_id(post_id)
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    action = await repo.react_to_post(current_user.id, post_id, ReactionType.FIRE)
    await db.commit()
    # "updated" happens if the user is switching from a non-fire reaction to
    # fire via the legacy button — treat that as "liked" too, since from the
    # old client's binary like/unlike perspective they now have a like.
    liked = action in ("added", "updated")
    return {"action": "liked" if liked else "unliked", "post_id": post_id}


@router.post("/{post_id}/comments", response_model=CommentResponse, status_code=201)
async def add_comment(
    post_id: int,
    payload: CommentCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = PostRepository(db)
    post = await repo.get_by_id(post_id)
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    comment = await repo.add_comment(post_id, current_user.id, payload.content)
    await db.commit()
    await db.refresh(comment)
    comment.author = current_user
    return comment
