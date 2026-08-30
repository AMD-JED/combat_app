"""Tests for v7 Open Mats: schedule-shape validation, and the RSVP flow."""
import pytest
from httpx import AsyncClient


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


async def create_gym(client: AsyncClient, token: str, name: str = "RSVP Gym") -> dict:
    resp = await client.post(
        "/api/v1/gyms/",
        json={"name": name, "location": "Oran", "sports": ["combat"]},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 201
    return resp.json()


@pytest.mark.asyncio
async def test_one_time_open_mat_requires_event_datetime(client: AsyncClient):
    token = await register_and_login(client, "om_owner1@test.com", "om_owner1")
    gym = await create_gym(client, token)

    resp = await client.post(
        f"/api/v1/gyms/{gym['id']}/open-mats",
        json={"title": "Sunday Session", "is_recurring": False},  # missing event_datetime
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_recurring_open_mat_requires_day_and_time(client: AsyncClient):
    token = await register_and_login(client, "om_owner2@test.com", "om_owner2")
    gym = await create_gym(client, token)

    resp = await client.post(
        f"/api/v1/gyms/{gym['id']}/open-mats",
        json={"title": "Weekly Rolls", "is_recurring": True},  # missing recurrence_day/start_time
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_one_time_open_mat_creation_and_detail(client: AsyncClient):
    token = await register_and_login(client, "om_owner3@test.com", "om_owner3")
    gym = await create_gym(client, token)

    resp = await client.post(
        f"/api/v1/gyms/{gym['id']}/open-mats",
        json={
            "title": "Sunday Session",
            "is_recurring": False,
            "event_datetime": "2026-09-06T10:00:00Z",
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 201, resp.text
    open_mat_id = resp.json()["id"]
    assert resp.json()["location"] == gym["location"]  # falls back to gym's location

    detail = await client.get(f"/api/v1/open-mats/{open_mat_id}")
    assert detail.status_code == 200
    assert detail.json()["title"] == "Sunday Session"
    assert detail.json()["rsvp_count"] == 0
    assert detail.json()["is_rsvped_by_me"] is False  # public/anonymous view


@pytest.mark.asyncio
async def test_rsvp_flow(client: AsyncClient):
    owner_token = await register_and_login(client, "om_owner4@test.com", "om_owner4")
    attendee_token = await register_and_login(client, "om_attendee4@test.com", "om_attendee4")
    gym = await create_gym(client, owner_token)

    created = await client.post(
        f"/api/v1/gyms/{gym['id']}/open-mats",
        json={
            "title": "Wednesday Drilling",
            "is_recurring": True,
            "recurrence_day": "wednesday",
            "start_time": "18:30:00",
        },
        headers={"Authorization": f"Bearer {owner_token}"},
    )
    open_mat_id = created.json()["id"]

    rsvp = await client.post(
        f"/api/v1/open-mats/{open_mat_id}/rsvp",
        headers={"Authorization": f"Bearer {attendee_token}"},
    )
    assert rsvp.status_code == 201
    assert rsvp.json()["user"]["username"] == "om_attendee4"

    dup_rsvp = await client.post(
        f"/api/v1/open-mats/{open_mat_id}/rsvp",
        headers={"Authorization": f"Bearer {attendee_token}"},
    )
    assert dup_rsvp.status_code == 400

    attendees = await client.get(f"/api/v1/open-mats/{open_mat_id}/attendees")
    assert attendees.status_code == 200
    assert len(attendees.json()) == 1

    cancel = await client.delete(
        f"/api/v1/open-mats/{open_mat_id}/rsvp",
        headers={"Authorization": f"Bearer {attendee_token}"},
    )
    assert cancel.status_code == 204

    attendees_after = await client.get(f"/api/v1/open-mats/{open_mat_id}/attendees")
    assert len(attendees_after.json()) == 0

    cancel_again = await client.delete(
        f"/api/v1/open-mats/{open_mat_id}/rsvp",
        headers={"Authorization": f"Bearer {attendee_token}"},
    )
    assert cancel_again.status_code == 400
