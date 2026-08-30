from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.repositories.sparring_repository import SparringRepository
from app.repositories.sport_repository import SportRepository, UserSportProfileRepository
from app.repositories.user_repository import UserRepository
from app.schemas.sparring import (
    SparringMatchSuggestion,
    SparringRequestAction,
    SparringRequestCreate,
    SparringRequestRespond,
    SparringRequestResponse,
)

router = APIRouter(prefix="/sparring", tags=["Sparring"])

COMBAT_SPORT_SLUG = "combat"

# action -> (statuses it's valid FROM, status it transitions TO, who may call it)
VALID_TRANSITIONS = {
    SparringRequestAction.ACCEPT: {"from": {"pending"}, "to": "accepted", "actor": "recipient"},
    SparringRequestAction.DECLINE: {"from": {"pending"}, "to": "declined", "actor": "recipient"},
    SparringRequestAction.CANCEL: {"from": {"pending", "accepted"}, "to": "cancelled", "actor": "requester"},
    SparringRequestAction.COMPLETE: {"from": {"accepted"}, "to": "completed", "actor": "either"},
}


@router.get("/suggestions", response_model=List[SparringMatchSuggestion])
async def get_match_suggestions(
    limit: int = 20,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Automatic sparring-partner suggestions, matched on the current user's
    'combat' sport profile: discipline (required match) + weight_class +
    belt_rank (each adds to match_score). Requires the current user to
    already have a 'combat' UserSportProfile (via POST /sports/me/profiles).
    """
    sport_repo = SportRepository(db)
    combat_sport = await sport_repo.get_by_slug(COMBAT_SPORT_SLUG)
    if not combat_sport:
        return []

    profile_repo = UserSportProfileRepository(db)
    my_profile = await profile_repo.get_by_user_and_sport(current_user.id, combat_sport.id)
    if not my_profile:
        raise HTTPException(
            status_code=400,
            detail="Add a 'combat' sport profile first (POST /sports/me/profiles) to get suggestions",
        )

    my_attrs = my_profile.attributes or {}
    my_discipline = my_attrs.get("discipline")
    my_weight_class = my_attrs.get("weight_class")
    my_belt_rank = my_attrs.get("belt_rank")

    if not my_discipline:
        raise HTTPException(
            status_code=400,
            detail="Your combat profile has no 'discipline' set — required for matching",
        )

    sparring_repo = SparringRepository(db)
    candidates = await sparring_repo.get_combat_matches(current_user.id, limit=limit)

    suggestions: List[SparringMatchSuggestion] = []
    for profile in candidates:
        attrs = profile.attributes or {}
        discipline = attrs.get("discipline")
        weight_class = attrs.get("weight_class")
        belt_rank = attrs.get("belt_rank")

        # Sport/discipline match is required — without it there's nothing
        # in common to suggest a sparring session over.
        if not discipline or discipline != my_discipline:
            continue

        score = 1
        matched_weight_class = None
        matched_belt_rank = None
        if weight_class and weight_class == my_weight_class:
            score += 1
            matched_weight_class = weight_class
        if belt_rank and belt_rank == my_belt_rank:
            score += 1
            matched_belt_rank = belt_rank

        suggestions.append(
            SparringMatchSuggestion(
                user=profile.user,
                shared_sport=discipline,
                shared_weight_class=matched_weight_class,
                shared_belt_rank=matched_belt_rank,
                match_score=score,
            )
        )

    suggestions.sort(key=lambda s: s.match_score, reverse=True)
    return suggestions[:limit]


@router.post("/requests", response_model=SparringRequestResponse, status_code=status.HTTP_201_CREATED)
async def create_sparring_request(
    payload: SparringRequestCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    if payload.recipient_id == current_user.id:
        raise HTTPException(status_code=400, detail="You cannot send a sparring request to yourself")

    user_repo = UserRepository(db)
    recipient = await user_repo.get_by_id(payload.recipient_id)
    if not recipient:
        raise HTTPException(status_code=404, detail="Recipient not found")

    sparring_repo = SparringRepository(db)
    existing = await sparring_repo.get_active_between(current_user.id, payload.recipient_id)
    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"An active sparring request already exists between you two (status: {existing.status})",
        )

    request = await sparring_repo.create_request(
        requester_id=current_user.id,
        recipient_id=payload.recipient_id,
        message=payload.message,
        scheduled_at=payload.scheduled_at,
        location=payload.location,
    )
    await db.commit()
    return await sparring_repo.get_with_users(request.id)


@router.get("/requests/incoming", response_model=List[SparringRequestResponse])
async def get_incoming_requests(
    status_filter: Optional[str] = None,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    sparring_repo = SparringRepository(db)
    return await sparring_repo.get_incoming(current_user.id, status_filter=status_filter)


@router.get("/requests/outgoing", response_model=List[SparringRequestResponse])
async def get_outgoing_requests(
    status_filter: Optional[str] = None,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    sparring_repo = SparringRepository(db)
    return await sparring_repo.get_outgoing(current_user.id, status_filter=status_filter)


@router.post("/requests/{request_id}/respond", response_model=SparringRequestResponse)
async def respond_to_sparring_request(
    request_id: int,
    payload: SparringRequestRespond,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    sparring_repo = SparringRepository(db)
    req = await sparring_repo.get_with_users(request_id)
    if not req:
        raise HTTPException(status_code=404, detail="Sparring request not found")

    is_requester = current_user.id == req.requester_id
    is_recipient = current_user.id == req.recipient_id
    if not is_requester and not is_recipient:
        raise HTTPException(status_code=403, detail="Not authorized to act on this request")

    rule = VALID_TRANSITIONS[payload.action]

    if rule["actor"] == "recipient" and not is_recipient:
        raise HTTPException(status_code=403, detail="Only the recipient can do this")
    if rule["actor"] == "requester" and not is_requester:
        raise HTTPException(status_code=403, detail="Only the requester can do this")
    # actor == "either" -> both requester and recipient are allowed, no extra check

    if req.status not in rule["from"]:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot '{payload.action.value}' a request with status '{req.status}'",
        )

    await sparring_repo.update(request_id, {"status": rule["to"]})
    await db.commit()
    return await sparring_repo.get_with_users(request_id)
