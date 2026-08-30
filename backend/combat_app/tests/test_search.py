"""Tests for the v7 unified search endpoint across users/gyms/open_mats/posts."""
import pytest
from httpx import AsyncClient


async def register_and_login(client: AsyncClient, email: str, username: str, full_name: str) -> str:
    await client.post("/api/v1/auth/register", json={
        "email": email,
        "username": username,
        "full_name": full_name,
        "password": "testpass123",
        "password_confirm": "testpass123",
    })
    resp = await client.post("/api/v1/auth/login", data={
        "username": email,
        "password": "testpass123",
    })
    return resp.json()["access_token"]


@pytest.mark.asyncio
async def test_search_requires_min_length(client: AsyncClient):
    resp = await client.get("/api/v1/search/", params={"q": "a"})
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_search_finds_user_gym_open_mat_and_post(client: AsyncClient):
    token = await register_and_login(
        client, "zenithfighter@test.com", "zenith_fighter", "Zenith Warrior"
    )

    gym_resp = await client.post(
        "/api/v1/gyms/",
        json={"name": "Zenith Combat Academy", "location": "Constantine", "sports": ["combat"]},
        headers={"Authorization": f"Bearer {token}"},
    )
    gym_id = gym_resp.json()["id"]

    await client.post(
        f"/api/v1/gyms/{gym_id}/open-mats",
        json={
            "title": "Zenith Open Roll",
            "is_recurring": True,
            "recurrence_day": "friday",
            "start_time": "19:00:00",
        },
        headers={"Authorization": f"Bearer {token}"},
    )

    await client.post(
        "/api/v1/posts/",
        json={"content": "Zenith training camp starts next week!"},
        headers={"Authorization": f"Bearer {token}"},
    )

    resp = await client.get("/api/v1/search/", params={"q": "Zenith"})
    assert resp.status_code == 200
    body = resp.json()

    assert any(u["username"] == "zenith_fighter" for u in body["users"])
    assert any(g["name"] == "Zenith Combat Academy" for g in body["gyms"])
    assert any(om["title"] == "Zenith Open Roll" for om in body["open_mats"])
    assert any("Zenith" in (p["content"] or "") for p in body["posts"])


@pytest.mark.asyncio
async def test_search_respects_limit_per_category(client: AsyncClient):
    token = await register_and_login(
        client, "limitowner@test.com", "limit_owner", "Limit Owner"
    )
    for i in range(3):
        resp = await client.post(
            "/api/v1/gyms/",
            json={"name": f"LimitGym {i}", "location": "Blida"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert resp.status_code == 201

    resp = await client.get("/api/v1/search/", params={"q": "LimitGym", "limit": 2})
    assert resp.status_code == 200
    assert len(resp.json()["gyms"]) == 2
