"""Tests for v8 personal training tracking."""
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.exercise import Exercise, ExerciseCategory, DifficultyLevel


async def seed_exercise(db_session: AsyncSession) -> int:
    exercise = Exercise(
        name="Heavy Bag Rounds",
        category=ExerciseCategory.CONDITIONING,
        difficulty=DifficultyLevel.INTERMEDIATE,
        description="Bag work",
        instructions="3x3min rounds",
    )
    db_session.add(exercise)
    await db_session.flush()
    await db_session.refresh(exercise)
    return exercise.id


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


@pytest.mark.asyncio
async def test_create_minimal_session(client: AsyncClient):
    """A session with just type/duration — no sport, gym, sparring link,
    and no exercises — must be accepted (all of those are optional)."""
    token = await register_and_login(client, "solo@test.com", "solo_fighter")
    resp = await client.post(
        "/api/v1/training/sessions",
        json={"session_type": "solo", "duration_minutes": 45, "intensity": 3},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["session_type"] == "solo"
    assert data["duration_minutes"] == 45
    assert data["exercise_logs"] == []


@pytest.mark.asyncio
async def test_create_session_with_exercises(client: AsyncClient, db_session: AsyncSession):
    token = await register_and_login(client, "detailed@test.com", "detailed_fighter")
    exercise_id = await seed_exercise(db_session)

    resp = await client.post(
        "/api/v1/training/sessions",
        json={
            "session_type": "conditioning",
            "duration_minutes": 30,
            "exercises": [
                {"exercise_id": exercise_id, "sets": 3, "duration_seconds": 180, "order_index": 0},
            ],
        },
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert len(data["exercise_logs"]) == 1
    assert data["exercise_logs"][0]["exercise_id"] == exercise_id


@pytest.mark.asyncio
async def test_create_session_with_unknown_exercise_fails(client: AsyncClient):
    token = await register_and_login(client, "badex@test.com", "badex_fighter")
    resp = await client.post(
        "/api/v1/training/sessions",
        json={
            "session_type": "solo",
            "duration_minutes": 20,
            "exercises": [{"exercise_id": 99999, "sets": 1}],
        },
        headers=auth_headers(token),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_list_sessions_only_returns_own(client: AsyncClient):
    token_a = await register_and_login(client, "a@test.com", "fighter_a")
    token_b = await register_and_login(client, "b@test.com", "fighter_b")

    await client.post(
        "/api/v1/training/sessions",
        json={"session_type": "solo", "duration_minutes": 10},
        headers=auth_headers(token_a),
    )

    resp_b = await client.get("/api/v1/training/sessions", headers=auth_headers(token_b))
    assert resp_b.status_code == 200
    assert resp_b.json() == []

    resp_a = await client.get("/api/v1/training/sessions", headers=auth_headers(token_a))
    assert resp_a.status_code == 200
    assert len(resp_a.json()) == 1


@pytest.mark.asyncio
async def test_get_other_users_session_forbidden(client: AsyncClient):
    token_a = await register_and_login(client, "owner@test.com", "owner_fighter")
    token_b = await register_and_login(client, "intruder@test.com", "intruder_fighter")

    create_resp = await client.post(
        "/api/v1/training/sessions",
        json={"session_type": "solo", "duration_minutes": 15},
        headers=auth_headers(token_a),
    )
    session_id = create_resp.json()["id"]

    resp = await client.get(
        f"/api/v1/training/sessions/{session_id}", headers=auth_headers(token_b)
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_delete_session(client: AsyncClient):
    token = await register_and_login(client, "deleter@test.com", "deleter_fighter")
    create_resp = await client.post(
        "/api/v1/training/sessions",
        json={"session_type": "solo", "duration_minutes": 20},
        headers=auth_headers(token),
    )
    session_id = create_resp.json()["id"]

    del_resp = await client.delete(
        f"/api/v1/training/sessions/{session_id}", headers=auth_headers(token)
    )
    assert del_resp.status_code == 204

    get_resp = await client.get(
        f"/api/v1/training/sessions/{session_id}", headers=auth_headers(token)
    )
    assert get_resp.status_code == 404
