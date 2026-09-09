"""
Notifications Endpoints (v10)
================================
POST   /notifications/device-tokens        ← register/re-parent an FCM token
DELETE /notifications/device-tokens        ← unregister (call on logout)
GET    /notifications                      ← paginated list
GET    /notifications/unread-count         ← lightweight polling fallback (see notification.py docstring)
POST   /notifications/{id}/read            ← mark one as read
POST   /notifications/read-all             ← mark all as read
DELETE /notifications/{id}                 ← delete one
"""
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.repositories.notification_repository import NotificationRepository
from app.schemas.notification import (
    DeviceTokenRegister,
    DeviceTokenUnregister,
    NotificationResponse,
    UnreadCountResponse,
)

router = APIRouter(prefix="/notifications", tags=["Notifications"])


@router.post("/device-tokens", status_code=status.HTTP_201_CREATED)
async def register_device_token(
    payload: DeviceTokenRegister,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = NotificationRepository(db)
    await repo.register_device_token(current_user.id, payload.fcm_token, payload.platform.value)
    await db.commit()
    return {"detail": "Device token registered"}


@router.delete("/device-tokens", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_device_token(
    payload: DeviceTokenUnregister,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """Call this on logout so a shared/reset device stops receiving
    pushes meant for the account that just signed out."""
    repo = NotificationRepository(db)
    await repo.unregister_device_token(current_user.id, payload.fcm_token)
    await db.commit()


@router.get("/unread-count", response_model=UnreadCountResponse)
async def get_unread_count(
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = NotificationRepository(db)
    count = await repo.get_unread_count(current_user.id)
    return UnreadCountResponse(unread_count=count)


@router.get("/", response_model=List[NotificationResponse])
async def get_notifications(
    skip: int = 0,
    limit: int = 50,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = NotificationRepository(db)
    return await repo.get_for_user(current_user.id, skip=skip, limit=limit)


@router.post("/{notification_id}/read")
async def mark_notification_read(
    notification_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = NotificationRepository(db)
    marked = await repo.mark_read(notification_id, current_user.id)
    if not marked:
        raise HTTPException(status_code=404, detail="Notification not found")
    await db.commit()
    return {"detail": "Marked as read"}


@router.post("/read-all")
async def mark_all_notifications_read(
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = NotificationRepository(db)
    count = await repo.mark_all_read(current_user.id)
    await db.commit()
    return {"marked_read": count}


@router.delete("/{notification_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_notification(
    notification_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = NotificationRepository(db)
    deleted = await repo.delete_for_user(notification_id, current_user.id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Notification not found")
    await db.commit()
