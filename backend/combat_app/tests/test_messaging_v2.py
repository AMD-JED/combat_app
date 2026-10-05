"""
Messaging redesign — backend additions:
  * POST /uploads/message/image|video
  * strict validation of message attachments (Cloudinary https URLs only)
  * `other_user_online` on the conversations list + `presence` WS broadcast
"""
import io
from unittest.mock import AsyncMock, patch

import pytest
from httpx import AsyncClient

IMG = "https://res.cloudinary.com/demo/image/upload/combat/messages/images/msg_1.jpg"
VID = "https://res.cloudinary.com/demo/video/upload/combat/messages/videos/msg_1.mp4"


async def register_and_login(client: AsyncClient, email: str, username: str) -> str:
    await client.post("/api/v1/auth/register", json={
        "email": email, "username": username, "full_name": "Test Fighter",
        "password": "testpass123", "password_confirm": "testpass123",
    })
    resp = await client.post("/api/v1/auth/login", data={"username": email, "password": "testpass123"})
    return resp.json()["access_token"]


def auth(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def make_conversation(client: AsyncClient):
    token_a = await register_and_login(client, "mv2_a@test.com", "mv2_a")
    token_b = await register_and_login(client, "mv2_b@test.com", "mv2_b")
    b_id = (await client.get("/api/v1/auth/me", headers=auth(token_b))).json()["id"]
    conv_id = (await client.post(f"/api/v1/messages/conversations/{b_id}", headers=auth(token_a))).json()["conversation_id"]
    return token_a, token_b, b_id, conv_id


# ── uploads ──────────────────────────────────────────────

@pytest.mark.asyncio
async def test_upload_message_image_requires_auth(client: AsyncClient):
    files = {"file": ("t.jpg", io.BytesIO(b"\xff\xd8\xff\xe0" + b"\x00" * 100), "image/jpeg")}
    resp = await client.post("/api/v1/uploads/message/image", files=files)
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_upload_message_image_success(client: AsyncClient):
    token = await register_and_login(client, "mv2_up@test.com", "mv2_up")
    files = {"file": ("t.jpg", io.BytesIO(b"\xff\xd8\xff\xe0" + b"\x00" * 100), "image/jpeg")}
    with patch("app.api.v1.endpoints.uploads.upload_message_image", new_callable=AsyncMock) as m:
        m.return_value = {"url": IMG, "public_id": "x", "width": 10, "height": 10}
        resp = await client.post("/api/v1/uploads/message/image", files=files, headers=auth(token))
    assert resp.status_code == 200
    assert resp.json()["url"] == IMG


@pytest.mark.asyncio
async def test_upload_message_video_success(client: AsyncClient):
    token = await register_and_login(client, "mv2_upv@test.com", "mv2_upv")
    files = {"file": ("t.mp4", io.BytesIO(b"\x00\x00\x00\x18ftypmp42" + b"\x00" * 100), "video/mp4")}
    with patch("app.api.v1.endpoints.uploads.upload_message_video", new_callable=AsyncMock) as m:
        m.return_value = {"url": VID, "public_id": "x", "duration": 3.0, "thumbnail_url": IMG}
        resp = await client.post("/api/v1/uploads/message/video", files=files, headers=auth(token))
    assert resp.status_code == 200
    assert resp.json()["thumbnail_url"] == IMG


def test_video_poster_url():
    from app.services.cloudinary_service import video_poster_url
    assert video_poster_url(VID) == (
        "https://res.cloudinary.com/demo/video/upload/so_1/combat/messages/videos/msg_1.jpg"
    )


# ── attachment validation ────────────────────────────────

@pytest.mark.asyncio
async def test_send_message_with_image_and_video(client: AsyncClient):
    token_a, _, _, conv_id = await make_conversation(client)
    url = f"/api/v1/messages/conversations/{conv_id}/messages"
    r1 = await client.post(url, json={"media_url": IMG, "media_type": "image"}, headers=auth(token_a))
    r2 = await client.post(url, json={"content": "clip", "media_url": VID, "media_type": "video"}, headers=auth(token_a))
    assert r1.status_code == 201 and r1.json()["media_type"] == "image"
    assert r2.status_code == 201 and r2.json()["media_url"] == VID


@pytest.mark.asyncio
@pytest.mark.parametrize("payload", [
    {"media_url": "https://evil.example.com/a.jpg", "media_type": "image"},   # foreign host
    {"media_url": "http://res.cloudinary.com/demo/a.jpg", "media_type": "image"},  # not https
    {"media_url": "https://res.cloudinary.com.evil.com/a.jpg", "media_type": "image"},  # look-alike host
    {"media_url": IMG},                                                        # missing media_type
    {"media_type": "image", "content": "x"},                                   # type without url
    {},                                                                        # empty message
])
async def test_send_message_rejects_bad_payloads(client: AsyncClient, payload):
    token_a, _, _, conv_id = await make_conversation(client)
    resp = await client.post(
        f"/api/v1/messages/conversations/{conv_id}/messages", json=payload, headers=auth(token_a)
    )
    assert resp.status_code == 422


def test_validate_message_payload_helper():
    from app.schemas.message import validate_message_payload
    validate_message_payload("hi", None, None)
    validate_message_payload(None, IMG, "image")
    with pytest.raises(ValueError):
        validate_message_payload(None, "https://x.com/a.jpg", "image")


# ── presence ─────────────────────────────────────────────

@pytest.mark.asyncio
async def test_conversations_report_other_user_online(client: AsyncClient):
    token_a, _, b_id, conv_id = await make_conversation(client)
    await client.post(
        f"/api/v1/messages/conversations/{conv_id}/messages", json={"content": "yo"}, headers=auth(token_a)
    )

    listing = (await client.get("/api/v1/messages/conversations", headers=auth(token_a))).json()
    assert listing[0]["other_user_online"] is False

    with patch("app.api.v1.endpoints.messages.manager.is_online", side_effect=lambda uid: uid == b_id):
        listing = (await client.get("/api/v1/messages/conversations", headers=auth(token_a))).json()
    assert listing[0]["other_user_online"] is True


@pytest.mark.asyncio
async def test_broadcast_presence_notifies_conversation_partners():
    from app.api.v1.endpoints.messages import _broadcast_presence

    class _U:
        def __init__(self, i): self.id = i

    class _Conv:
        def __init__(self, other): self._o = other
        def other_user(self, _uid): return _U(self._o)

    class _Repo:
        async def get_user_conversations(self, _uid): return [_Conv(7), _Conv(9)]

    with patch("app.api.v1.endpoints.messages.manager.send_to_user", new_callable=AsyncMock) as send:
        await _broadcast_presence(1, True, _Repo())

    sent = {c.args[0]: c.args[1] for c in send.await_args_list}
    assert set(sent) == {7, 9}
    assert sent[7] == {"event": "presence", "data": {"user_id": 1, "is_online": True}}
