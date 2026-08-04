from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime, timezone

from app.core.database import get_db
from app.core.security import (
    hash_password, verify_password,
    create_access_token, create_refresh_token, decode_token
)
from app.core.dependencies import get_current_active_user, oauth2_scheme
from app.core.redis_client import blacklist_token
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.schemas.user import UserCreate, UserPrivateResponse, TokenResponse, TokenRefreshRequest

from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

router = APIRouter(prefix="/auth", tags=["Authentication"] )


@router.post("/register", response_model=UserPrivateResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("3/minute")
async def register(request: Request, payload: UserCreate, db: AsyncSession = Depends(get_db)):
    repo = UserRepository(db)

    if await repo.get_by_email(payload.email):
        raise HTTPException(status_code=400, detail="Email already registered")

    if await repo.get_by_username(payload.username):
        raise HTTPException(status_code=400, detail="Username already taken")

    user = User(
        email=payload.email,
        username=payload.username,
        full_name=payload.full_name,
        hashed_password=hash_password(payload.password),
    )
    return await repo.create(user)


@router.post("/login", response_model=TokenResponse)
@limiter.limit("5/minute")
async def login(request: Request, form: OAuth2PasswordRequestForm = Depends(), db: AsyncSession = Depends(get_db)):
    repo = UserRepository(db)
    user = await repo.get_by_email(form.username)  # username field = email

    if not user or not verify_password(form.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        )

    if not user.is_active:
        raise HTTPException(status_code=400, detail="Account is deactivated")

    return TokenResponse(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
    )


@router.post("/refresh", response_model=TokenResponse)
@limiter.limit("10/minute")
async def refresh_token(request: Request, payload: TokenRefreshRequest, db: AsyncSession = Depends(get_db)):
    token_data = decode_token(payload.refresh_token)

    if not token_data or token_data.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    repo = UserRepository(db)
    user = await repo.get_by_id(int(token_data["sub"]))
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="User not found or inactive")

    return TokenResponse(
        access_token=create_access_token(user.id),
        refresh_token=create_refresh_token(user.id),
    )


@router.get("/me", response_model=UserPrivateResponse)
async def get_me(current_user: User = Depends(get_current_active_user)):
    return current_user


@router.post("/logout", status_code=status.HTTP_200_OK)
async def logout(
    token: str = Depends(oauth2_scheme),
    current_user: User = Depends(get_current_active_user),
):
    payload = decode_token(token)
    if payload:
        jti = payload.get("jti")
        exp = payload.get("exp")
        if jti and exp:
            now_ts = datetime.now(timezone.utc).timestamp()
            remaining = int(exp - now_ts)
            await blacklist_token(jti, remaining)

    return {"detail": "Successfully logged out"}