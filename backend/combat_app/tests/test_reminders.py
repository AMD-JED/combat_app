"""Tests for v10 Session Reminders."""
from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.models.notification import SessionReminder
from app.repositories.notification_repository import SessionReminderRepository
from app.services import reminder_scheduler


async def register_and_login(client: AsyncClient, email: str, username: str) -> str:
    await client.post("/api/v1/auth/register", json={
        "email": email,
        "username": username,
        "full_name": "Test Fighter",
        "password": "testpass123",
        "password_confirm": "testpass123",
    })
    resp = await client.post("/api/v1/auth/login", data={
        "username": email,
        "password": "testpass123",
    })
    return resp.json()["access_token"]


def auth_headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def create_session(client: AsyncClient, token: str, session_date: datetime) -> int:
    resp = await client.post(
        "/api/v1/training/sessions",
        json={
            "session_type": "solo",
            "duration_minutes": 30,
            "intensity": 3,
            "session_date": session_date.isoformat(),
        },
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


@pytest.mark.asyncio
async def test_create_reminder_computes_remind_at_correctly(client: AsyncClient):
    token = await register_and_login(client, "reminderuser@test.com", "reminder_user")
    session_date = datetime.now(timezone.utc) + timedelta(days=1)
    session_id = await create_session(client, token, session_date)

    resp = await client.post(
        "/api/v1/reminders/",
        json={"session_id": session_id, "lead_time": "30m"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["lead_time"] == "30m"
    assert data["sent"] is False

    remind_at = datetime.fromisoformat(data["remind_at"])
    if remind_at.tzinfo is None:
        remind_at = remind_at.replace(tzinfo=timezone.utc)
    expected = session_date - timedelta(minutes=30)
    assert abs((remind_at - expected).total_seconds()) < 2


@pytest.mark.asyncio
async def test_exact_lead_time_means_remind_at_equals_session_date(client: AsyncClient):
    token = await register_and_login(client, "exactreminder@test.com", "exact_reminder")
    session_date = datetime.now(timezone.utc) + timedelta(hours=5)
    session_id = await create_session(client, token, session_date)

    resp = await client.post(
        "/api/v1/reminders/",
        json={"session_id": session_id, "lead_time": "exact"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201
    remind_at = datetime.fromisoformat(resp.json()["remind_at"])
    if remind_at.tzinfo is None:
        remind_at = remind_at.replace(tzinfo=timezone.utc)
    assert abs((remind_at - session_date).total_seconds()) < 2


@pytest.mark.asyncio
async def test_cannot_set_reminder_for_someone_elses_session(client: AsyncClient):
    owner_token = await register_and_login(client, "sessionowner@test.com", "session_owner")
    intruder_token = await register_and_login(client, "sessionintruder@test.com", "session_intruder")

    session_id = await create_session(client, owner_token, datetime.now(timezone.utc) + timedelta(hours=1))

    resp = await client.post(
        "/api/v1/reminders/",
        json={"session_id": session_id, "lead_time": "30m"},
        headers=auth_headers(intruder_token),
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_reminder_for_nonexistent_session_404s(client: AsyncClient):
    token = await register_and_login(client, "ghostreminder@test.com", "ghost_reminder")
    resp = await client.post(
        "/api/v1/reminders/",
        json={"session_id": 999999, "lead_time": "30m"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_list_and_delete_own_reminders(client: AsyncClient):
    token = await register_and_login(client, "listreminder@test.com", "list_reminder")
    session_id = await create_session(client, token, datetime.now(timezone.utc) + timedelta(hours=2))

    create_resp = await client.post(
        "/api/v1/reminders/",
        json={"session_id": session_id, "lead_time": "1h"},
        headers=auth_headers(token),
    )
    reminder_id = create_resp.json()["id"]

    list_resp = await client.get("/api/v1/reminders/", headers=auth_headers(token))
    assert len(list_resp.json()) == 1

    delete_resp = await client.delete(f"/api/v1/reminders/{reminder_id}", headers=auth_headers(token))
    assert delete_resp.status_code == 204

    list_after = await client.get("/api/v1/reminders/", headers=auth_headers(token))
    assert list_after.json() == []


@pytest.mark.asyncio
async def test_only_owner_can_delete_reminder(client: AsyncClient):
    owner_token = await register_and_login(client, "delowner@test.com", "del_reminder_owner")
    intruder_token = await register_and_login(client, "delintruder@test.com", "del_reminder_intruder")

    session_id = await create_session(client, owner_token, datetime.now(timezone.utc) + timedelta(hours=3))
    create_resp = await client.post(
        "/api/v1/reminders/",
        json={"session_id": session_id, "lead_time": "1h"},
        headers=auth_headers(owner_token),
    )
    reminder_id = create_resp.json()["id"]

    forbidden = await client.delete(f"/api/v1/reminders/{reminder_id}", headers=auth_headers(intruder_token))
    assert forbidden.status_code == 403


@pytest.mark.asyncio
async def test_scheduler_tick_pushes_due_reminder_and_marks_sent(client: AsyncClient, db_session, monkeypatch):
    """Exercises app/services/reminder_scheduler._tick() directly against
    a due (already-past) reminder, bypassing the real 60s wall-clock wait
    — this is the only realistic way to test a periodic job without
    actually sleeping in the test suite.

    reminder_scheduler._tick() opens its OWN session via the module-level
    AsyncSessionLocal (it runs outside any request, so there's no
    Depends(get_db) to override) — that name is bound to the app's REAL
    settings.DATABASE_URL, not conftest's in-memory TestingSessionLocal.
    Monkeypatching it here to point at the same in-memory engine the rest
    of this test uses is what makes the tick see the reminder we just
    inserted via db_session.
    """
    from conftest import TestingSessionLocal
    monkeypatch.setattr(reminder_scheduler, "AsyncSessionLocal", TestingSessionLocal)

    token = await register_and_login(client, "ticktest@test.com", "tick_test_user")
    user_resp = await client.get("/api/v1/auth/me", headers=auth_headers(token))
    user_id = user_resp.json()["id"]

    session_id = await create_session(client, token, datetime.now(timezone.utc) + timedelta(minutes=5))

    reminder_repo = SessionReminderRepository(db_session)
    reminder = await reminder_repo.create_reminder(
        user_id=user_id,
        session_id=session_id,
        lead_time="30m",
        remind_at=datetime.now(timezone.utc) - timedelta(seconds=5),  # already due
    )
    await db_session.commit()

    await reminder_scheduler._tick()

    await db_session.refresh(reminder)
    assert reminder.sent is True

    notifs = await client.get("/api/v1/notifications/", headers=auth_headers(token))
    items = notifs.json()
    assert any(n["type"] == "session_reminder" for n in items)


@pytest.mark.asyncio
async def test_scheduler_tick_ignores_not_yet_due_reminders(client: AsyncClient, db_session, monkeypatch):
    from conftest import TestingSessionLocal
    monkeypatch.setattr(reminder_scheduler, "AsyncSessionLocal", TestingSessionLocal)

    token = await register_and_login(client, "notdue@test.com", "not_due_user")
    user_id = (await client.get("/api/v1/auth/me", headers=auth_headers(token))).json()["id"]

    session_id = await create_session(client, token, datetime.now(timezone.utc) + timedelta(days=1))

    reminder_repo = SessionReminderRepository(db_session)
    reminder = await reminder_repo.create_reminder(
        user_id=user_id,
        session_id=session_id,
        lead_time="30m",
        remind_at=datetime.now(timezone.utc) + timedelta(hours=23),  # far in the future
    )
    await db_session.commit()

    await reminder_scheduler._tick()

    result = await db_session.execute(select(SessionReminder).where(SessionReminder.id == reminder.id))
    refreshed = result.scalar_one()
    assert refreshed.sent is False

    notifs = await client.get("/api/v1/notifications/", headers=auth_headers(token))
    assert notifs.json() == []
