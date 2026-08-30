from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.repositories.search_repository import SearchRepository
from app.schemas.search import SearchResults

router = APIRouter(prefix="/search", tags=["Search"])


@router.get("/", response_model=SearchResults)
async def unified_search(
    q: str = Query(..., min_length=2),
    limit: int = Query(5, ge=1, le=20, description="Max results per category"),
    db: AsyncSession = Depends(get_db),
):
    """Public. Searches athletes, gyms, open mats, and posts in parallel
    (well — sequentially, but each is a single cheap ILIKE query; see
    app/repositories/search_repository.py for why there's no join)."""
    repo = SearchRepository(db)
    return SearchResults(
        users=await repo.search_users(q, limit=limit),
        gyms=await repo.search_gyms(q, limit=limit),
        open_mats=await repo.search_open_mats(q, limit=limit),
        posts=await repo.search_posts(q, limit=limit),
    )
