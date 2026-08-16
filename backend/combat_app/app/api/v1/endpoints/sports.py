from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.repositories.sport_repository import SportRepository, UserSportProfileRepository
from app.schemas.sport import (
    SportResponse,
    UserSportProfileCreate,
    UserSportProfileResponse,
    UserSportProfileUpdate,
    validate_sport_attributes,
)

router = APIRouter(prefix="/sports", tags=["Sports"])


@router.get("/", response_model=List[SportResponse])
async def list_sports(db: AsyncSession = Depends(get_db)):
    """قائمة كل الرياضات المفعّلة على المنصة."""
    repo = SportRepository(db)
    return await repo.get_active_sports()


@router.get("/me/profiles", response_model=List[UserSportProfileResponse])
async def get_my_sport_profiles(
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """كل الملفات الرياضية الخاصة بالمستخدم الحالي (قد يملك أكثر من واحد)."""
    repo = UserSportProfileRepository(db)
    return await repo.get_for_user(current_user.id)


@router.post(
    "/me/profiles",
    response_model=UserSportProfileResponse,
    status_code=status.HTTP_201_CREATED,
)
async def add_sport_profile(
    payload: UserSportProfileCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """
    إضافة رياضة جديدة لملف المستخدم.
    attributes يتم التحقق منها تلقائيًا حسب sport_slug (انظر app/schemas/sport.py).
    """
    sport_repo = SportRepository(db)
    sport = await sport_repo.get_by_slug(payload.sport_slug)
    if not sport:
        raise HTTPException(
            status_code=404, detail=f"الرياضة '{payload.sport_slug}' غير موجودة"
        )

    profile_repo = UserSportProfileRepository(db)
    existing = await profile_repo.get_by_user_and_sport(current_user.id, sport.id)
    if existing:
        raise HTTPException(
            status_code=400, detail="المستخدم يملك ملفًا لهذه الرياضة مسبقًا"
        )

    if payload.is_primary:
        await profile_repo.unset_primary_for_user(current_user.id)

    profile = await profile_repo.create_for_user(
        user_id=current_user.id,
        sport_id=sport.id,
        is_primary=payload.is_primary,
        attributes=payload.attributes,
    )
    await db.commit()
    return await profile_repo.get_with_sport(profile.id)


@router.patch("/me/profiles/{profile_id}", response_model=UserSportProfileResponse)
async def update_sport_profile(
    profile_id: int,
    payload: UserSportProfileUpdate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """تعديل ملف رياضي موجود. لا يمكن تغيير نوع الرياضة نفسها من هنا."""
    profile_repo = UserSportProfileRepository(db)
    profile = await profile_repo.get_with_sport(profile_id)
    if not profile or profile.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="الملف الرياضي غير موجود")

    update_data: dict = {}

    if payload.attributes is not None:
        try:
            update_data["attributes"] = validate_sport_attributes(
                profile.sport.slug, payload.attributes
            )
        except ValueError as exc:
            raise HTTPException(status_code=422, detail=str(exc)) from exc

    if payload.is_primary is not None:
        if payload.is_primary:
            await profile_repo.unset_primary_for_user(current_user.id)
        update_data["is_primary"] = payload.is_primary

    if update_data:
        await profile_repo.update(profile_id, update_data)
        await db.commit()

    return await profile_repo.get_with_sport(profile_id)


@router.delete("/me/profiles/{profile_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_sport_profile(
    profile_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """حذف رياضة من ملف المستخدم."""
    profile_repo = UserSportProfileRepository(db)
    profile = await profile_repo.get_by_id(profile_id)
    if not profile or profile.user_id != current_user.id:
        raise HTTPException(status_code=404, detail="الملف الرياضي غير موجود")
    await profile_repo.delete(profile_id)
    await db.commit()
