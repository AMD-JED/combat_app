"""Story replies must be visible: tagged in the conversation and pushed live."""
from unittest.mock import AsyncMock, patch

import pytest
from httpx import AsyncClient

IMG = "https://res.cloudinary.com/demo/image/upload/combat/stories/images/s1.jpg"


async def register_and_login(client: AsyncClient, email: str, username: str) -> str:
    await client.post("/api/v1/auth/register", json={
        "email": email, "username": username, "full_name": "Test Fighter",
        "password": "testpass123", "password_confirm": "testpass123",
    })
    resp = await client.post("/api/v1/auth/login", data={"username": email, "password": "testpass123"})
    return resp.json()["access_token"]


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def user_id(client: AsyncClient, token: str) -> int:
    return (await client.get("/api/v1/auth/me", headers=auth(token))).json()["id"]


async def make_story(client: AsyncClient, token: str) -> int:
    resp = await client.post(
        "/api/v1/stories/", json={"content_type": "image", "media_url": IMG}, headers=auth(token)
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


@pytest.mark.asyncio
async def test_story_reply_is_tagged_in_messages_and_conversations(client: AsyncClient):
    owner = await register_and_login(client, "sr_o@test.com", "sr_owner")
    fan = await register_and_login(client, "sr_f@test.com", "sr_fan")
    story_id = await make_story(client, owner)

    reply = await client.post(
        f"/api/v1/stories/{story_id}/reply", json={"content": "Great shot!"}, headers=auth(fan)
    )
    assert reply.status_code == 201, reply.text
    conv_id = reply.json()["conversation_id"]

    # Both participants see the message tagged with the story it answers.
    for token in (owner, fan):
        msgs = (await client.get(
            f"/api/v1/messages/conversations/{conv_id}/messages", headers=auth(token)
        )).json()
        assert len(msgs) == 1
        assert msgs[0]["content"] == "Great shot!"
        assert msgs[0]["reply_to_story_id"] == story_id

    # ...and the conversation list's last message carries the tag too.
    listing = (await client.get("/api/v1/messages/conversations", headers=auth(owner))).json()
    assert listing[0]["last_message"]["reply_to_story_id"] == story_id
    assert listing[0]["unread_count"] == 1


@pytest.mark.asyncio
async def test_story_reply_is_pushed_live_to_author_and_replier(client: AsyncClient):
    owner = await register_and_login(client, "srp_o@test.com", "srp_owner")
    fan = await register_and_login(client, "srp_f@test.com", "srp_fan")
    owner_id = await user_id(client, owner)
    fan_id = await user_id(client, fan)
    story_id = await make_story(client, owner)

    with patch("app.api.v1.endpoints.messages.manager.send_to_user", new_callable=AsyncMock) as send:
        resp = await client.post(
            f"/api/v1/stories/{story_id}/reply", json={"content": "🔥"}, headers=auth(fan)
        )
    assert resp.status_code == 201

    sent = {call.args[0]: call.args[1] for call in send.await_args_list}
    assert set(sent) == {owner_id, fan_id}
    for payload in sent.values():
        assert payload["event"] == "new_message"
        assert payload["data"]["reply_to_story_id"] == story_id
        assert payload["data"]["content"] == "🔥"
        assert payload["data"]["sender"]["id"] == fan_id


@pytest.mark.asyncio
async def test_rest_send_message_is_pushed_live(client: AsyncClient):
    a = await register_and_login(client, "rs_a@test.com", "rs_a")
    b = await register_and_login(client, "rs_b@test.com", "rs_b")
    a_id = await user_id(client, a)
    b_id = await user_id(client, b)
    conv_id = (await client.post(f"/api/v1/messages/conversations/{b_id}", headers=auth(a))).json()["conversation_id"]

    with patch("app.api.v1.endpoints.messages.manager.send_to_user", new_callable=AsyncMock) as send:
        resp = await client.post(
            f"/api/v1/messages/conversations/{conv_id}/messages",
            json={"content": "via REST"},
            headers=auth(a),
        )
    assert resp.status_code == 201

    sent = {call.args[0]: call.args[1] for call in send.await_args_list}
    assert set(sent) == {a_id, b_id}
    assert sent[b_id]["data"]["content"] == "via REST"
    assert sent[b_id]["data"]["reply_to_story_id"] is None


@pytest.mark.asyncio
async def test_plain_messages_have_no_story_tag(client: AsyncClient):
    a = await register_and_login(client, "pn_a@test.com", "pn_a")
    b = await register_and_login(client, "pn_b@test.com", "pn_b")
    b_id = await user_id(client, b)
    conv_id = (await client.post(f"/api/v1/messages/conversations/{b_id}", headers=auth(a))).json()["conversation_id"]
    resp = await client.post(
        f"/api/v1/messages/conversations/{conv_id}/messages", json={"content": "hi"}, headers=auth(a)
    )
    assert resp.status_code == 201
    assert resp.json()["reply_to_story_id"] is None
