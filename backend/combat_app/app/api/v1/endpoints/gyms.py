from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.gym import Gym
from app.models.user import User
from app.repositories.gym_repository import GymRepository
from app.repositories.open_mat_repository import OpenMatRepository
from app.schemas.gym import GymCreate, GymMemberResponse, GymResponse, GymUpdate
from app.schemas.open_mat import OpenMatCreate, OpenMatResponse

router = APIRouter(prefix="/gyms", tags=["Gyms"])


def _to_gym_response(gym: Gym, member_count: int) -> GymResponse:
    return GymResponse(
        id=gym.id,
        name=gym.name,
        description=gym.description,
        location=gym.location,
        sports=gym.sports or [],
        contact_phone=gym.contact_phone,
        contact_email=gym.contact_email,
        is_active=gym.is_active,
        owner=gym.owner,
        member_count=member_count,
        created_at=gym.created_at,
        updated_at=gym.updated_at,
    )


async def _to_open_mat_response(
    open_mat, repo: OpenMatRepository, current_user_id: Optional[int]
) -> OpenMatResponse:
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


@router.post("/", response_model=GymResponse, status_code=status.HTTP_201_CREATED)
async def create_gym(
    payload: GymCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """Any authenticated user can create a gym — they become its owner
    (a GymMembership row with role='owner' is created automatically)."""
    repo = GymRepository(db)
    gym = await repo.create_with_owner(current_user.id, payload.model_dump())
    await db.commit()
    gym = await repo.get_with_owner(gym.id)
    member_count = await repo.count_members(gym.id)
    return _to_gym_response(gym, member_count)


@router.get("/", response_model=List[GymResponse])
async def list_gyms(
    skip: int = 0,
    limit: int = 20,
    db: AsyncSession = Depends(get_db),
):
    repo = GymRepository(db)
    gyms = await repo.list_active(skip=skip, limit=limit)
    return [_to_gym_response(g, await repo.count_members(g.id)) for g in gyms]


@router.get("/{gym_id}", response_model=GymResponse)
async def get_gym(gym_id: int, db: AsyncSession = Depends(get_db)):
    repo = GymRepository(db)
    gym = await repo.get_with_owner(gym_id)
    if not gym:
        raise HTTPException(status_code=404, detail="Gym not found")
    member_count = await repo.count_members(gym_id)
    return _to_gym_response(gym, member_count)


@router.patch("/{gym_id}", response_model=GymResponse)
async def update_gym(
    gym_id: int,
    payload: GymUpdate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = GymRepository(db)
    gym = await repo.get_by_id(gym_id)
    if not gym:
        raise HTTPException(status_code=404, detail="Gym not found")
    if gym.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the gym owner can edit it")

    update_data = payload.model_dump(exclude_unset=True)
    if update_data:
        await repo.update(gym_id, update_data)
    await db.commit()

    gym = await repo.get_with_owner(gym_id)
    member_count = await repo.count_members(gym_id)
    return _to_gym_response(gym, member_count)


@router.delete("/{gym_id}", status_code=status.HTTP_204_NO_CONTENT)
async def deactivate_gym(
    gym_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """Soft delete — sets is_active=False rather than removing the row,
    since sparring_requests / open_mats may still reference this gym."""
    repo = GymRepository(db)
    gym = await repo.get_by_id(gym_id)
    if not gym:
        raise HTTPException(status_code=404, detail="Gym not found")
    if gym.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the gym owner can deactivate it")

    await repo.update(gym_id, {"is_active": False})
    await db.commit()


@router.post("/{gym_id}/join", response_model=GymMemberResponse, status_code=status.HTTP_201_CREATED)
async def join_gym(
    gym_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = GymRepository(db)
    gym = await repo.get_by_id(gym_id)
    if not gym or not gym.is_active:
        raise HTTPException(status_code=404, detail="Gym not found")

    membership = await repo.join(gym_id, current_user.id)
    if not membership:
        raise HTTPException(status_code=400, detail="Already a member of this gym")
    await db.commit()

    membership = await repo.get_membership(gym_id, current_user.id)
    return membership


@router.delete("/{gym_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
async def leave_gym(
    gym_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = GymRepository(db)
    left = await repo.leave(gym_id, current_user.id)
    if not left:
        raise HTTPException(
            status_code=400,
            detail="Not a member, or you're the owner (transfer ownership before leaving)",
        )
    await db.commit()


@router.get("/{gym_id}/members", response_model=List[GymMemberResponse])
async def list_gym_members(gym_id: int, db: AsyncSession = Depends(get_db)):
    repo = GymRepository(db)
    gym = await repo.get_by_id(gym_id)
    if not gym:
        raise HTTPException(status_code=404, detail="Gym not found")
    return await repo.list_members(gym_id)


@router.post(
    "/{gym_id}/open-mats", response_model=OpenMatResponse, status_code=status.HTTP_201_CREATED
)
async def create_open_mat(
    gym_id: int,
    payload: OpenMatCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    gym_repo = GymRepository(db)
    gym = await gym_repo.get_by_id(gym_id)
    if not gym or not gym.is_active:
        raise HTTPException(status_code=404, detail="Gym not found")
    if gym.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the gym owner can schedule open mats")

    om_repo = OpenMatRepository(db)
    data = payload.model_dump()
    open_mat = await om_repo.create(
        om_repo.model(gym_id=gym_id, created_by=current_user.id, **data)
    )
    await db.commit()

    open_mat = await om_repo.get_with_gym(open_mat.id)
    return await _to_open_mat_response(open_mat, om_repo, current_user.id)


@router.get("/{gym_id}/open-mats", response_model=List[OpenMatResponse])
async def list_gym_open_mats(
    gym_id: int,
    db: AsyncSession = Depends(get_db),
):
    gym_repo = GymRepository(db)
    gym = await gym_repo.get_by_id(gym_id)
    if not gym:
        raise HTTPException(status_code=404, detail="Gym not found")

    om_repo = OpenMatRepository(db)
    open_mats = await om_repo.list_for_gym(gym_id)
    return [await _to_open_mat_response(om, om_repo, None) for om in open_mats]
