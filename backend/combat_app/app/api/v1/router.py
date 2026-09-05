from fastapi import APIRouter
from app.api.v1.endpoints import (
    auth, users, posts, exercises, uploads, messages, sports, sparring,
    gyms, open_mats, search, training, ai_coach,
)

api_router = APIRouter(prefix="/api/v1")

api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(posts.router)
api_router.include_router(exercises.router)
api_router.include_router(uploads.router)
api_router.include_router(messages.router)
api_router.include_router(sports.router)
api_router.include_router(sparring.router)
api_router.include_router(gyms.router)
api_router.include_router(open_mats.router)
api_router.include_router(search.router)
api_router.include_router(training.router)
api_router.include_router(ai_coach.router)
