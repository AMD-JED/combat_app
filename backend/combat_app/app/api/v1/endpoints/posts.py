from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.models.post import Post, PostType
from app.repositories.post_repository import PostRepository
from app.repositories.user_repository import UserRepository
from app.schemas.post import PostCreate, PostUpdate, PostResponse, CommentCreate, CommentResponse

router = APIRouter(prefix="/posts", tags=["Posts"])


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
        PostResponse(
            **{c.key: getattr(p, c.key) for c in p.__table__.columns},
            author=p.author,
            likes_count=len(p.liked_by),
            comments_count=len(p.comments),
        )
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
    return PostResponse(
        id=created.id,
        content=created.content,
        media_url=created.media_url,
        post_type=created.post_type,
        tags=created.tags,
        author=current_user,
        likes_count=0,
        comments_count=0,
        created_at=created.created_at,
    )


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


@router.post("/{post_id}/like")
async def toggle_like(
    post_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = PostRepository(db)
    post = await repo.get_by_id(post_id)
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    liked = await repo.like_post(current_user.id, post_id)
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
    comment.author = current_user
    return comment
