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




# ──────────────────────────────────────────────────────────────────────────
# Regression tests: `open_conversation` / `mark_read` / `delete_message` used
# to return a 200/204 without ever calling `db.commit()`. The `client`
# fixture above can't catch this class of bug — it commits after every
# successful request regardless of what the endpoint itself does, which is
# exactly what let this hide. `strict_client` mirrors the real `get_db()`
# (no auto-commit), so these only pass if the endpoint commits its own work.
# ──────────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_open_conversation_persists_across_requests(strict_client: AsyncClient):
    token_a = await register_and_login(strict_client, "persist_a@test.com", "persist_a")
    token_b = await register_and_login(strict_client, "persist_b@test.com", "persist_b")
    me_b = await strict_client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token_b}"})
    user_b_id = me_b.json()["id"]

    open_resp = await strict_client.post(
        f"/api/v1/messages/conversations/{user_b_id}",
        headers={"Authorization": f"Bearer {token_a}"},
    )
    conv_id = open_resp.json()["conversation_id"]

    # A brand-new request/session must still see this conversation.
    resp = await strict_client.get(
        f"/api/v1/messages/conversations/{conv_id}/messages",
        headers={"Authorization": f"Bearer {token_a}"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json() == []

    listing = await strict_client.get(
        "/api/v1/messages/conversations", headers={"Authorization": f"Bearer {token_a}"}
    )
    assert any(c["id"] == conv_id for c in listing.json())


@pytest.mark.asyncio
async def test_mark_read_persists_across_requests(strict_client: AsyncClient):
    token_a = await register_and_login(strict_client, "persist_read_a@test.com", "persist_read_a")
    token_b = await register_and_login(strict_client, "persist_read_b@test.com", "persist_read_b")
    me_b = await strict_client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token_b}"})
    user_b_id = me_b.json()["id"]

    conv_id = (await strict_client.post(
        f"/api/v1/messages/conversations/{user_b_id}",
        headers={"Authorization": f"Bearer {token_a}"},
    )).json()["conversation_id"]

    await strict_client.post(
        f"/api/v1/messages/conversations/{conv_id}/messages",
        json={"content": "hi B"},
        headers={"Authorization": f"Bearer {token_a}"},
    )

    mark = await strict_client.post(
        f"/api/v1/messages/conversations/{conv_id}/read",
        headers={"Authorization": f"Bearer {token_b}"},
    )
    assert mark.status_code == 200
    assert mark.json()["marked_read"] == 1

    # Fresh request/session: the unread count for B must have actually
    # persisted as cleared, not just in the response of the /read call.
    listing = await strict_client.get(
        "/api/v1/messages/conversations", headers={"Authorization": f"Bearer {token_b}"}
    )
    conv = next(c for c in listing.json() if c["id"] == conv_id)
    assert conv["unread_count"] == 0


@pytest.mark.asyncio
async def test_delete_message_persists_across_requests(strict_client: AsyncClient):
    token_a = await register_and_login(strict_client, "persist_del_a@test.com", "persist_del_a")
    token_b = await register_and_login(strict_client, "persist_del_b@test.com", "persist_del_b")
    me_b = await strict_client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token_b}"})
    user_b_id = me_b.json()["id"]

    conv_id = (await strict_client.post(
        f"/api/v1/messages/conversations/{user_b_id}",
        headers={"Authorization": f"Bearer {token_a}"},
    )).json()["conversation_id"]

    sent = await strict_client.post(
        f"/api/v1/messages/conversations/{conv_id}/messages",
        json={"content": "oops"},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    message_id = sent.json()["id"]

    delete_resp = await strict_client.delete(
        f"/api/v1/messages/{message_id}", headers={"Authorization": f"Bearer {token_a}"}
    )
    assert delete_resp.status_code == 204

    # Fresh request/session: the soft-delete must have actually persisted.
    history = await strict_client.get(
        f"/api/v1/messages/conversations/{conv_id}/messages",
        headers={"Authorization": f"Bearer {token_a}"},
    )
    # NOTE: the REST schema deliberately still carries the raw `content`
    # after a soft-delete (only the WebSocket's `_msg_to_dict` nulls it out)
    # — `MessageModel.displayContent` on the Flutter side is what actually
    # hides it, by checking `deleted_at`, not `content`. So `deleted_at`
    # being set is the real, persisted contract to check here.
    msg = next(m for m in history.json() if m["id"] == message_id)
    assert msg["deleted_at"] is not None



@pytest.mark.asyncio
async def test_conversations_list_shows_the_latest_message(client: AsyncClient):
    """Regression guard: two messages landing in the same wall-clock second
    (`created_at` only has whole-second resolution) used to leave the OLDER
    one showing as the conversation's preview, because the ORDER BY had no
    tiebreaker for equal timestamps."""
    token_a = await register_and_login(client, "order_a@test.com", "order_a")
    token_b = await register_and_login(client, "order_b@test.com", "order_b")
    me_b = await client.get("/api/v1/auth/me", headers={"Authorization": f"Bearer {token_b}"})
    user_b_id = me_b.json()["id"]

    conv_id = (await client.post(
        f"/api/v1/messages/conversations/{user_b_id}",
        headers={"Authorization": f"Bearer {token_a}"},
    )).json()["conversation_id"]

    await client.post(
        f"/api/v1/messages/conversations/{conv_id}/messages",
        json={"content": "older message"},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    newer = await client.post(
        f"/api/v1/messages/conversations/{conv_id}/messages",
        json={"content": "newer message"},
        headers={"Authorization": f"Bearer {token_a}"},
    )
    newer_id = newer.json()["id"]

    listing = await client.get(
        "/api/v1/messages/conversations", headers={"Authorization": f"Bearer {token_a}"}
    )
    conv = next(c for c in listing.json() if c["id"] == conv_id)
    assert conv["last_message"]["id"] == newer_id
    assert conv["last_message"]["content"] == "newer message"

    history = await client.get(
        f"/api/v1/messages/conversations/{conv_id}/messages",
        headers={"Authorization": f"Bearer {token_a}"},
    )
    # Newest first (the endpoint's own documented order; the client reverses
    # it for display) -- the newer message's id must lead.
    assert history.json()[0]["id"] == newer_id

