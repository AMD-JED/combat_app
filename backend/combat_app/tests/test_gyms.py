"""Tests for the v7 Gyms system: CRUD, ownership, membership, and the
nested open-mat creation/listing under a gym."""
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


async def get_my_id(client: AsyncClient, token: str) -> int:
    resp = await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    return resp.json()["id"]


async def create_gym(client: AsyncClient, token: str, name: str = "Iron Gym") -> dict:
    resp = await client.post(
        "/api/v1/gyms/",
        json={
            "name": name,
            "description": "A serious training gym",
            "location": "Algiers",
            "sports": ["combat"],
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_create_gym_makes_creator_owner(client: AsyncClient):
    token = await register_and_login(client, "gymowner1@test.com", "gym_owner1")
    my_id = await get_my_id(client, token)

    gym = await create_gym(client, token)
    assert gym["owner"]["id"] == my_id
    assert gym["member_count"] == 1  # owner counts as a member
    assert gym["sports"] == ["combat"]
    assert gym["is_active"] is True


@pytest.mark.asyncio
async def test_list_and_get_gym(client: AsyncClient):
    token = await register_and_login(client, "gymowner2@test.com", "gym_owner2")
    created = await create_gym(client, token, name="Apex MMA")

    listing = await client.get("/api/v1/gyms/")
    assert listing.status_code == 200
    assert any(g["id"] == created["id"] for g in listing.json())

    detail = await client.get(f"/api/v1/gyms/{created['id']}")
    assert detail.status_code == 200
    assert detail.json()["name"] == "Apex MMA"


@pytest.mark.asyncio
async def test_only_owner_can_update_gym(client: AsyncClient):
    owner_token = await register_and_login(client, "gymowner3@test.com", "gym_owner3")
    stranger_token = await register_and_login(client, "gymstranger3@test.com", "gym_stranger3")
    gym = await create_gym(client, owner_token)

    forbidden = await client.patch(
        f"/api/v1/gyms/{gym['id']}",
        json={"name": "Hijacked Gym"},
        headers={"Authorization": f"Bearer {stranger_token}"},
    )
    assert forbidden.status_code == 403

    allowed = await client.patch(
        f"/api/v1/gyms/{gym['id']}",
        json={"name": "Renamed Gym"},
        headers={"Authorization": f"Bearer {owner_token}"},
    )
    assert allowed.status_code == 200
    assert allowed.json()["name"] == "Renamed Gym"


@pytest.mark.asyncio
async def test_only_owner_can_deactivate_gym(client: AsyncClient):
    owner_token = await register_and_login(client, "gymowner4@test.com", "gym_owner4")
    stranger_token = await register_and_login(client, "gymstranger4@test.com", "gym_stranger4")
    gym = await create_gym(client, owner_token)

    forbidden = await client.delete(
        f"/api/v1/gyms/{gym['id']}", headers={"Authorization": f"Bearer {stranger_token}"}
    )
    assert forbidden.status_code == 403

    allowed = await client.delete(
        f"/api/v1/gyms/{gym['id']}", headers={"Authorization": f"Bearer {owner_token}"}
    )
    assert allowed.status_code == 204

    listing = await client.get("/api/v1/gyms/")
    assert not any(g["id"] == gym["id"] for g in listing.json())


@pytest.mark.asyncio
async def test_join_leave_and_list_members(client: AsyncClient):
    owner_token = await register_and_login(client, "gymowner5@test.com", "gym_owner5")
    member_token = await register_and_login(client, "gymmember5@test.com", "gym_member5")
    member_id = await get_my_id(client, member_token)
    gym = await create_gym(client, owner_token)

    join = await client.post(
        f"/api/v1/gyms/{gym['id']}/join", headers={"Authorization": f"Bearer {member_token}"}
    )
    assert join.status_code == 201
    assert join.json()["role"] == "member"

    dup_join = await client.post(
        f"/api/v1/gyms/{gym['id']}/join", headers={"Authorization": f"Bearer {member_token}"}
    )
    assert dup_join.status_code == 400

    members = await client.get(f"/api/v1/gyms/{gym['id']}/members")
    assert members.status_code == 200
    assert len(members.json()) == 2  # owner + member
    assert any(m["user"]["id"] == member_id for m in members.json())

    leave = await client.delete(
        f"/api/v1/gyms/{gym['id']}/leave", headers={"Authorization": f"Bearer {member_token}"}
    )
    assert leave.status_code == 204

    members_after = await client.get(f"/api/v1/gyms/{gym['id']}/members")
    assert len(members_after.json()) == 1


@pytest.mark.asyncio
async def test_owner_cannot_leave_their_own_gym(client: AsyncClient):
    owner_token = await register_and_login(client, "gymowner6@test.com", "gym_owner6")
    gym = await create_gym(client, owner_token)

    resp = await client.delete(
        f"/api/v1/gyms/{gym['id']}/leave", headers={"Authorization": f"Bearer {owner_token}"}
    )
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_only_owner_can_create_open_mat_for_gym(client: AsyncClient):
    owner_token = await register_and_login(client, "gymowner7@test.com", "gym_owner7")
    stranger_token = await register_and_login(client, "gymstranger7@test.com", "gym_stranger7")
    gym = await create_gym(client, owner_token)

    forbidden = await client.post(
        f"/api/v1/gyms/{gym['id']}/open-mats",
        json={
            "title": "Saturday Rolls",
            "is_recurring": True,
            "recurrence_day": "saturday",
            "start_time": "10:00:00",
        },
        headers={"Authorization": f"Bearer {stranger_token}"},
    )
    assert forbidden.status_code == 403

    allowed = await client.post(
        f"/api/v1/gyms/{gym['id']}/open-mats",
        json={
            "title": "Saturday Rolls",
            "is_recurring": True,
            "recurrence_day": "saturday",
            "start_time": "10:00:00",
        },
        headers={"Authorization": f"Bearer {owner_token}"},
    )
    assert allowed.status_code == 201, allowed.text
    assert allowed.json()["gym_name"] == gym["name"]
    assert allowed.json()["recurrence_day"] == "saturday"

    listing = await client.get(f"/api/v1/gyms/{gym['id']}/open-mats")
    assert listing.status_code == 200
    assert len(listing.json()) == 1
