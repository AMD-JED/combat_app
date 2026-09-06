"""Tests for v9 Stories + Highlights."""
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


async def get_user_id(client: AsyncClient, token: str) -> int:
    resp = await client.get("/api/v1/auth/me", headers=auth_headers(token))
    return resp.json()["id"]


@pytest.mark.asyncio
async def test_create_text_story(client: AsyncClient):
    token = await register_and_login(client, "storyteller@test.com", "storyteller")
    resp = await client.post(
        "/api/v1/stories/",
        json={"content_type": "text", "text_content": "Fight night! 🥊", "background_color": "#111827"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["content_type"] == "text"
    assert data["text_content"] == "Fight night! 🥊"
    assert data["views_count"] == 0
    assert data["expires_at"] > data["created_at"]


@pytest.mark.asyncio
async def test_create_story_missing_required_content_rejected(client: AsyncClient):
    token = await register_and_login(client, "badstory@test.com", "badstory")
    # image content_type with no media_url must fail validation
    resp = await client.post(
        "/api/v1/stories/",
        json={"content_type": "image"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_view_story_records_view_and_owner_sees_viewer_list(client: AsyncClient):
    owner_token = await register_and_login(client, "owner@test.com", "story_owner")
    viewer_token = await register_and_login(client, "viewer@test.com", "story_viewer")

    create_resp = await client.post(
        "/api/v1/stories/",
        json={"content_type": "text", "text_content": "Who's watching?"},
        headers=auth_headers(owner_token),
    )
    story_id = create_resp.json()["id"]

    # Viewer opens the story -> records a view
    view_resp = await client.get(f"/api/v1/stories/{story_id}", headers=auth_headers(viewer_token))
    assert view_resp.status_code == 200
    assert view_resp.json()["viewed_by_me"] is True

    # Owner checks the "seen by" list
    views_resp = await client.get(f"/api/v1/stories/{story_id}/views", headers=auth_headers(owner_token))
    assert views_resp.status_code == 200
    viewers = views_resp.json()
    assert len(viewers) == 1
    assert viewers[0]["viewer"]["username"] == "story_viewer"

    # A non-owner cannot see the viewer list
    forbidden = await client.get(f"/api/v1/stories/{story_id}/views", headers=auth_headers(viewer_token))
    assert forbidden.status_code == 403


@pytest.mark.asyncio
async def test_followers_only_story_hidden_from_non_followers(client: AsyncClient):
    owner_token = await register_and_login(client, "private_owner@test.com", "private_owner")
    stranger_token = await register_and_login(client, "stranger@test.com", "stranger_user")

    create_resp = await client.post(
        "/api/v1/stories/",
        json={"content_type": "text", "text_content": "Followers only!", "visibility": "followers"},
        headers=auth_headers(owner_token),
    )
    story_id = create_resp.json()["id"]

    resp = await client.get(f"/api/v1/stories/{story_id}", headers=auth_headers(stranger_token))
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_delete_story_removes_it_from_highlight(client: AsyncClient):
    token = await register_and_login(client, "highlighter@test.com", "highlighter")

    story_resp = await client.post(
        "/api/v1/stories/",
        json={"content_type": "text", "text_content": "Pin me!"},
        headers=auth_headers(token),
    )
    story_id = story_resp.json()["id"]

    highlight_resp = await client.post(
        "/api/v1/highlights/",
        json={"title": "Best Moments", "story_ids": [story_id]},
        headers=auth_headers(token),
    )
    assert highlight_resp.status_code == 201, highlight_resp.text
    highlight_id = highlight_resp.json()["id"]
    assert len(highlight_resp.json()["stories"]) == 1

    # Deleting the story cascades it out of the highlight (confirmed v9 decision)
    del_resp = await client.delete(f"/api/v1/stories/{story_id}", headers=auth_headers(token))
    assert del_resp.status_code == 204

    get_resp = await client.get(f"/api/v1/highlights/{highlight_id}", headers=auth_headers(token))
    assert get_resp.status_code == 200
    assert get_resp.json()["stories"] == []


@pytest.mark.asyncio
async def test_reply_to_story_creates_dm_message(client: AsyncClient):
    owner_token = await register_and_login(client, "replyowner@test.com", "reply_owner")
    replier_token = await register_and_login(client, "replier@test.com", "replier_user")

    story_resp = await client.post(
        "/api/v1/stories/",
        json={"content_type": "text", "text_content": "React to this!"},
        headers=auth_headers(owner_token),
    )
    story_id = story_resp.json()["id"]

    reply_resp = await client.post(
        f"/api/v1/stories/{story_id}/reply",
        json={"content": "Great story!"},
        headers=auth_headers(replier_token),
    )
    assert reply_resp.status_code == 201, reply_resp.text
    conv_id = reply_resp.json()["conversation_id"]

    messages_resp = await client.get(
        f"/api/v1/messages/conversations/{conv_id}/messages", headers=auth_headers(owner_token)
    )
    assert messages_resp.status_code == 200
    messages = messages_resp.json()
    assert any(m["content"] == "Great story!" for m in messages)


@pytest.mark.asyncio
async def test_cannot_reply_to_own_story(client: AsyncClient):
    token = await register_and_login(client, "selfreply@test.com", "self_replier")
    story_resp = await client.post(
        "/api/v1/stories/",
        json={"content_type": "text", "text_content": "Talking to myself"},
        headers=auth_headers(token),
    )
    story_id = story_resp.json()["id"]

    resp = await client.post(
        f"/api/v1/stories/{story_id}/reply",
        json={"content": "hi me"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 400
