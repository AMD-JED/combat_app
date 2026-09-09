"""
Session Reminders Endpoints (v10)
====================================
POST   /reminders/          ← schedule a reminder for one of your training sessions
GET    /reminders/          ← your scheduled reminders
DELETE /reminders/{id}      ← cancel one
"""
from datetime import timedelta
from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.models.user import User
from app.repositories.notification_repository import SessionReminderRepository
from app.repositories.training_repository import TrainingRepository
from app.schemas.notification import (
    LEAD_TIME_MINUTES,
    SessionReminderCreate,
    SessionReminderResponse,
)

router = APIRouter(prefix="/reminders", tags=["Session Reminders"])


@router.post("/", response_model=SessionReminderResponse, status_code=status.HTTP_201_CREATED)
async def create_reminder(
    payload: SessionReminderCreate,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    training_repo = TrainingRepository(db)
    session = await training_repo.get_by_id(payload.session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Training session not found")
    if session.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="You can only set reminders for your own sessions")

    lead_minutes = LEAD_TIME_MINUTES[payload.lead_time.value]
    remind_at = session.session_date - timedelta(minutes=lead_minutes)

    repo = SessionReminderRepository(db)
    reminder = await repo.create_reminder(
        user_id=current_user.id,
        session_id=payload.session_id,
        lead_time=payload.lead_time.value,
        remind_at=remind_at,
    )
    await db.commit()
    return reminder


@router.get("/", response_model=List[SessionReminderResponse])
async def get_my_reminders(
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = SessionReminderRepository(db)
    return await repo.get_for_user(current_user.id)


@router.delete("/{reminder_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_reminder(
    reminder_id: int,
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    repo = SessionReminderRepository(db)
    reminder = await repo.get_by_id(reminder_id)
    if not reminder:
        raise HTTPException(status_code=404, detail="Reminder not found")
    if reminder.user_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not authorized")
    await repo.delete(reminder_id)
    await db.commit()
