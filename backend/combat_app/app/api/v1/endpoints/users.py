from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.schemas.user import UserPublicResponse, UserUpdate

router = APIRouter(prefix="/users", tags=["Users"])


@router.get("/search", response_model=List[UserPublicResponse])
async def search_users(
    q: str = Query(..., min_length=2),
    skip: int = 0,
    limit: int = 20,
    db: AsyncSession = Depends(get_db),
):
    repo = UserRepository(db)
    return await repo.search(q, skip=skip, limit=limit)


@router.get("/{username}", response_model=UserPublicResponse)
async def get_user_profile(username: str, db: AsyncSession = Depends(get_db)):
    repo = UserRepository(db)
    user = await repo.get_by_username(username)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.patch("/me", response_model=UserPublicResponse)
async def update_profile(
    payload: UserUpdate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = UserRepository(db)
    update_data = payload.model_dump(exclude_unset=True)
    return await repo.update(current_user.id, update_data)


@router.post("/{user_id}/follow", status_code=200)
async def toggle_follow(
    user_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="You cannot follow yourself")

    repo = UserRepository(db)
    target = await repo.get_by_id(user_id)
    if not target:
        raise HTTPException(status_code=404, detail="User not found")

    followed = await repo.follow(current_user.id, user_id)
    if not followed:
        await repo.unfollow(current_user.id, user_id)
        return {"action": "unfollowed", "user_id": user_id}
    return {"action": "followed", "user_id": user_id}


@router.get("/{user_id}/followers", response_model=List[UserPublicResponse])
async def get_followers(user_id: int, db: AsyncSession = Depends(get_db)):
    repo = UserRepository(db)
    user = await repo.get_with_relations(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user.followers


@router.get("/{user_id}/following", response_model=List[UserPublicResponse])
async def get_following(user_id: int, db: AsyncSession = Depends(get_db)):
    repo = UserRepository(db)
    user = await repo.get_with_relations(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user.following
