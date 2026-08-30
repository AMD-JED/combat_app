from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.repositories.open_mat_repository import OpenMatRepository
from app.schemas.open_mat import OpenMatResponse, OpenMatRSVPResponse

router = APIRouter(prefix="/open-mats", tags=["Open Mats"])


async def _to_open_mat_response(
    open_mat, repo: OpenMatRepository, current_user_id: Optional[int]
) -> OpenMatResponse:
    """Mirrors app/api/v1/endpoints/gyms.py:_to_open_mat_response — kept
    as a local copy rather than a shared import to avoid a circular
    dependency between the two endpoint modules over something this
    small."""
    rsvp_count = await repo.count_rsvps(open_mat.id)
    is_rsvped = False
    if current_user_id is not None:
        is_rsvped = (await repo.get_rsvp(open_mat.id, current_user_id)) is not None
    return OpenMatResponse(
        id=open_mat.id,
        gym_id=open_mat.gym_id,
        gym_name=open_mat.gym.name if open_mat.gym else "",
        title=open_mat.title,
        description=open_mat.description,
        is_recurring=open_mat.is_recurring,
        event_datetime=open_mat.event_datetime,
        recurrence_day=open_mat.recurrence_day,
        start_time=open_mat.start_time,
        end_time=open_mat.end_time,
        location=open_mat.location_override or (open_mat.gym.location if open_mat.gym else None),
        rsvp_count=rsvp_count,
        is_rsvped_by_me=is_rsvped,
        created_at=open_mat.created_at,
    )


@router.get("/{open_mat_id}", response_model=OpenMatResponse)
async def get_open_mat(
    open_mat_id: int,
    db: AsyncSession = Depends(get_db),
):
    """Public — no auth required, same as GET /gyms/{id} and GET
    /users/{username}. is_rsvped_by_me is always False for anonymous
    viewers since there's no current_user to check against."""
    repo = OpenMatRepository(db)
    open_mat = await repo.get_with_gym(open_mat_id)
    if not open_mat:
        raise HTTPException(status_code=404, detail="Open mat not found")
    return await _to_open_mat_response(open_mat, repo, None)


@router.post("/{open_mat_id}/rsvp", response_model=OpenMatRSVPResponse, status_code=status.HTTP_201_CREATED)
async def rsvp_to_open_mat(
    open_mat_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = OpenMatRepository(db)
    open_mat = await repo.get_by_id(open_mat_id)
    if not open_mat:
        raise HTTPException(status_code=404, detail="Open mat not found")

    entry = await repo.rsvp(open_mat_id, current_user.id)
    if not entry:
        raise HTTPException(status_code=400, detail="Already RSVP'd to this open mat")
    await db.commit()

    entry = await repo.get_rsvp(open_mat_id, current_user.id)
    return entry


@router.delete("/{open_mat_id}/rsvp", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_rsvp(
    open_mat_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = OpenMatRepository(db)
    cancelled = await repo.cancel_rsvp(open_mat_id, current_user.id)
    if not cancelled:
        raise HTTPException(status_code=400, detail="You haven't RSVP'd to this open mat")
    await db.commit()


@router.get("/{open_mat_id}/attendees", response_model=List[OpenMatRSVPResponse])
async def list_attendees(open_mat_id: int, db: AsyncSession = Depends(get_db)):
    repo = OpenMatRepository(db)
    open_mat = await repo.get_by_id(open_mat_id)
    if not open_mat:
        raise HTTPException(status_code=404, detail="Open mat not found")
    return await repo.list_rsvps(open_mat_id)
