"""
Auth Service
============
Business logic for authentication: registration, login, token refresh, logout.

Separating this from the endpoint layer allows:
  - Unit testing without HTTP server
  - Reuse in admin panels, background tasks, CLI tools
  - Adding Notifications (e.g., welcome email) without touching the endpoint

TODO: Add the following services as the app grows:
  - user_service.py    ← profile management, search, follow stats
  - post_service.py    ← feed ranking, like notifications, content moderation
  - message_service.py ← conversation creation, read receipts, push notifications
  - upload_service.py  ← file quota management, NSFW detection
"""

from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status

from app.core.security import hash_password, verify_password, create_access_token, create_refresh_token
from app.models.user import User
from app.repositories.user_repository import UserRepository
from app.schemas.user import UserCreate, TokenResponse


class AuthService:

    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = UserRepository(db)

    async def register(self, payload: UserCreate) -> User:
        """
        Validates uniqueness, hashes password, persists user.
        Raises HTTPException on email/username collision.
        """
        if await self.repo.get_by_email(payload.email):
            raise HTTPException(status_code=400, detail="Email already registered")

        if await self.repo.get_by_username(payload.username):
            raise HTTPException(status_code=400, detail="Username already taken")

        user = User(
            email=payload.email,
            username=payload.username,
            full_name=payload.full_name,
            hashed_password=hash_password(payload.password),
        )
        created = await self.repo.create(user)
        await self.db.commit()
        await self.db.refresh(created)
        return created

    async def login(self, email: str, password: str) -> TokenResponse:
        """
        Validates credentials and returns access + refresh tokens.
        Raises HTTPException on invalid credentials or inactive account.
        """
        user = await self.repo.get_by_email(email)

        if not user or not verify_password(password, user.hashed_password):
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
