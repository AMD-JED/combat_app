from fastapi import APIRouter
from app.api.v1.endpoints import auth, users, posts, exercises, uploads, messages

api_router = APIRouter(prefix="/api/v1")

api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(posts.router)
api_router.include_router(exercises.router)
api_router.include_router(uploads.router)
api_router.include_router(messages.router)
