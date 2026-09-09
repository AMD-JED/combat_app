"""Tests for v10 Notifications.

FIREBASE_CREDENTIALS_JSON is empty in the test .env, so every push
attempt inside notification_service.create_and_push hits the expected
RuntimeError branch and is swallowed — these tests verify the DB side
(the actual source of truth) works regardless of push configuration,
exactly as designed.
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


def auth_headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def create_post(client: AsyncClient, token: str, content: str = "hello") -> int:
    resp = await client.post(
        "/api/v1/posts/", json={"content": content}, headers=auth_headers(token)
    )
    return resp.json()["id"]


@pytest.mark.asyncio
async def test_reaction_on_others_post_creates_notification(client: AsyncClient):
    author_token = await register_and_login(client, "notif_author@test.com", "notif_author")
    reactor_token = await register_and_login(client, "notif_reactor@test.com", "notif_reactor")

    post_id = await create_post(client, author_token)

    react_resp = await client.post(
        f"/api/v1/posts/{post_id}/react", json={"reaction_type": "fire"}, headers=auth_headers(reactor_token)
    )
    assert react_resp.status_code == 200

    notifs = await client.get("/api/v1/notifications/", headers=auth_headers(author_token))
    assert notifs.status_code == 200
    items = notifs.json()
    assert len(items) == 1
    assert items[0]["type"] == "reaction"
    assert items[0]["actor"]["username"] == "notif_reactor"
    assert items[0]["is_read"] is False


@pytest.mark.asyncio
async def test_reacting_to_own_post_creates_no_notification(client: AsyncClient):
    token = await register_and_login(client, "selfreact@test.com", "self_reactor")
    post_id = await create_post(client, token)

    await client.post(
        f"/api/v1/posts/{post_id}/react", json={"reaction_type": "fire"}, headers=auth_headers(token)
    )

    notifs = await client.get("/api/v1/notifications/", headers=auth_headers(token))
    assert notifs.json() == []


@pytest.mark.asyncio
async def test_comment_on_post_creates_notification(client: AsyncClient):
    author_token = await register_and_login(client, "commentauthor@test.com", "comment_author")
    commenter_token = await register_and_login(client, "commenter2@test.com", "commenter_two")

    post_id = await create_post(client, author_token)

    await client.post(
        f"/api/v1/posts/{post_id}/comments",
        json={"content": "nice!"},
        headers=auth_headers(commenter_token),
    )

    notifs = await client.get("/api/v1/notifications/", headers=auth_headers(author_token))
    items = notifs.json()
    assert len(items) == 1
    assert items[0]["type"] == "comment"
    assert items[0]["data"]["post_id"] == post_id


@pytest.mark.asyncio
async def test_comment_on_reel_creates_notification(client: AsyncClient):
    author_token = await register_and_login(client, "reelnotifauthor@test.com", "reel_notif_author")
    commenter_token = await register_and_login(client, "reelnotifcommenter@test.com", "reel_notif_commenter")

    reel_resp = await client.post(
        "/api/v1/reels/", json={"media_url": "https://cdn.example.com/x.mp4"}, headers=auth_headers(author_token)
    )
    reel_id = reel_resp.json()["id"]

    await client.post(
        f"/api/v1/reels/{reel_id}/comments",
        json={"content": "solid combo"},
        headers=auth_headers(commenter_token),
    )

    notifs = await client.get("/api/v1/notifications/", headers=auth_headers(author_token))
    items = notifs.json()
    assert len(items) == 1
    assert items[0]["type"] == "comment"
    assert items[0]["data"]["reel_id"] == reel_id


@pytest.mark.asyncio
async def test_sparring_request_and_response_create_notifications(client: AsyncClient):
    requester_token = await register_and_login(client, "sparreq@test.com", "sparring_requester")
    recipient_token = await register_and_login(client, "sparrec@test.com", "sparring_recipient")

    recipient_id = (await client.get("/api/v1/auth/me", headers=auth_headers(recipient_token))).json()["id"]

    create_resp = await client.post(
        "/api/v1/sparring/requests",
        json={"recipient_id": recipient_id},
        headers=auth_headers(requester_token),
    )
    assert create_resp.status_code == 201, create_resp.text
    request_id = create_resp.json()["id"]

    recipient_notifs = (await client.get("/api/v1/notifications/", headers=auth_headers(recipient_token))).json()
    assert len(recipient_notifs) == 1
    assert recipient_notifs[0]["type"] == "sparring_request"

    respond_resp = await client.post(
        f"/api/v1/sparring/requests/{request_id}/respond",
        json={"action": "accept"},
        headers=auth_headers(recipient_token),
    )
    assert respond_resp.status_code == 200, respond_resp.text

    requester_notifs = (await client.get("/api/v1/notifications/", headers=auth_headers(requester_token))).json()
    assert len(requester_notifs) == 1
    assert requester_notifs[0]["type"] == "sparring_response"
    assert requester_notifs[0]["data"]["status"] == "accepted"


@pytest.mark.asyncio
async def test_new_message_creates_notification(client: AsyncClient):
    sender_token = await register_and_login(client, "msgsender@test.com", "msg_sender")
    recipient_token = await register_and_login(client, "msgrecipient@test.com", "msg_recipient")

    recipient_id = (await client.get("/api/v1/auth/me", headers=auth_headers(recipient_token))).json()["id"]

    open_resp = await client.post(
        f"/api/v1/messages/conversations/{recipient_id}", headers=auth_headers(sender_token)
    )
    conversation_id = open_resp.json()["conversation_id"]

    await client.post(
        f"/api/v1/messages/conversations/{conversation_id}/messages",
        json={"content": "yo, ready to spar?"},
        headers=auth_headers(sender_token),
    )

    notifs = (await client.get("/api/v1/notifications/", headers=auth_headers(recipient_token))).json()
    assert len(notifs) == 1
    assert notifs[0]["type"] == "message"


@pytest.mark.asyncio
async def test_unread_count_mark_read_and_mark_all_read(client: AsyncClient):
    author_token = await register_and_login(client, "unreadauthor@test.com", "unread_author")
    reactor_token = await register_and_login(client, "unreadreactor@test.com", "unread_reactor")

    post_id = await create_post(client, author_token)
    await client.post(
        f"/api/v1/posts/{post_id}/react", json={"reaction_type": "fire"}, headers=auth_headers(reactor_token)
    )
    await client.post(
        f"/api/v1/posts/{post_id}/comments", json={"content": "hi"}, headers=auth_headers(reactor_token)
    )

    count_resp = await client.get("/api/v1/notifications/unread-count", headers=auth_headers(author_token))
    assert count_resp.json()["unread_count"] == 2

    notifs = (await client.get("/api/v1/notifications/", headers=auth_headers(author_token))).json()
    first_id = notifs[0]["id"]

    read_resp = await client.post(f"/api/v1/notifications/{first_id}/read", headers=auth_headers(author_token))
    assert read_resp.status_code == 200

    count_after_one_read = await client.get("/api/v1/notifications/unread-count", headers=auth_headers(author_token))
    assert count_after_one_read.json()["unread_count"] == 1

    mark_all_resp = await client.post("/api/v1/notifications/read-all", headers=auth_headers(author_token))
    assert mark_all_resp.json()["marked_read"] == 1

    final_count = await client.get("/api/v1/notifications/unread-count", headers=auth_headers(author_token))
    assert final_count.json()["unread_count"] == 0


@pytest.mark.asyncio
async def test_cannot_mark_or_delete_someone_elses_notification(client: AsyncClient):
    author_token = await register_and_login(client, "protectedauthor@test.com", "protected_author")
    reactor_token = await register_and_login(client, "protectedreactor@test.com", "protected_reactor")
    intruder_token = await register_and_login(client, "intruder@test.com", "intruder_user")

    post_id = await create_post(client, author_token)
    await client.post(
        f"/api/v1/posts/{post_id}/react", json={"reaction_type": "fire"}, headers=auth_headers(reactor_token)
    )
    notif_id = (await client.get("/api/v1/notifications/", headers=auth_headers(author_token))).json()[0]["id"]

    forbidden_read = await client.post(f"/api/v1/notifications/{notif_id}/read", headers=auth_headers(intruder_token))
    assert forbidden_read.status_code == 404

    forbidden_delete = await client.delete(f"/api/v1/notifications/{notif_id}", headers=auth_headers(intruder_token))
    assert forbidden_delete.status_code == 404


@pytest.mark.asyncio
async def test_device_token_register_and_unregister(client: AsyncClient):
    token = await register_and_login(client, "device@test.com", "device_user")

    register_resp = await client.post(
        "/api/v1/notifications/device-tokens",
        json={"fcm_token": "fake-fcm-token-abc123", "platform": "android"},
        headers=auth_headers(token),
    )
    assert register_resp.status_code == 201

    # Re-registering the same token (e.g. app restart) must not error
    again_resp = await client.post(
        "/api/v1/notifications/device-tokens",
        json={"fcm_token": "fake-fcm-token-abc123", "platform": "android"},
        headers=auth_headers(token),
    )
    assert again_resp.status_code == 201

    unregister_resp = await client.request(
        "DELETE",
        "/api/v1/notifications/device-tokens",
        json={"fcm_token": "fake-fcm-token-abc123"},
        headers=auth_headers(token),
    )
    assert unregister_resp.status_code == 204


@pytest.mark.asyncio
async def test_device_token_reparents_to_new_owner(client: AsyncClient, db_session):
    """A token belonging to user A that gets registered by user B (device
    changed hands via logout/login) should move to B, not error out or
    create a duplicate row — see DeviceToken docstring."""
    from sqlalchemy import select
    from app.models.notification import DeviceToken

    token_a = await register_and_login(client, "devicea@test.com", "device_user_a")
    token_b = await register_and_login(client, "deviceb@test.com", "device_user_b")

    shared_fcm_token = "shared-device-token-xyz"

    await client.post(
        "/api/v1/notifications/device-tokens",
        json={"fcm_token": shared_fcm_token, "platform": "android"},
        headers=auth_headers(token_a),
    )
    await client.post(
        "/api/v1/notifications/device-tokens",
        json={"fcm_token": shared_fcm_token, "platform": "android"},
        headers=auth_headers(token_b),
    )

    result = await db_session.execute(select(DeviceToken).where(DeviceToken.fcm_token == shared_fcm_token))
    rows = result.scalars().all()
    assert len(rows) == 1

    user_b_id = (await client.get("/api/v1/auth/me", headers=auth_headers(token_b))).json()["id"]
    assert rows[0].user_id == user_b_id
