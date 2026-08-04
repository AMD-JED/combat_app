"""
Tests for Direct Messaging REST endpoints.
WebSocket tests require a real event loop and are integration tests.
"""
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


@pytest.mark.asyncio
async def test_open_conversation(client: AsyncClient):
    token_a = await register_and_login(client, "fighter_a@test.com", "fighter_a")
    token_b = await register_and_login(client, "fighter_b@test.com", "fighter_b")

    # Get user B's ID
    me_b = await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token_b}"})
    user_b_id = me_b.json()["id"]

    # A opens conversation with B
    resp = await client.post(
        f"/api/v1/messages/conversations/{user_b_id}",
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert resp.status_code == 200
    assert "conversation_id" in resp.json()


@pytest.mark.asyncio
async def test_cannot_message_yourself(client: AsyncClient):
    token = await register_and_login(client, "solo@test.com", "solo_fighter")
    me = await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"})
    my_id = me.json()["id"]

    resp = await client.post(
        f"/api/v1/messages/conversations/{my_id}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_list_conversations_empty(client: AsyncClient):
    token = await register_and_login(client, "empty@test.com", "empty_fighter")
    resp = await client.get(
        "/api/v1/messages/conversations",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_get_messages_unauthorized(client: AsyncClient):
    token_a = await register_and_login(client, "msg_a@test.com", "msg_fighter_a")
    resp = await client.get(
        "/api/v1/messages/conversations/999/messages",
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert resp.status_code == 403
