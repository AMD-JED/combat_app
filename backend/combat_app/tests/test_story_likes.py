"""v11 — story likes + captions on image/video stories."""
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


async def make_story(client: AsyncClient, token: str, **extra) -> dict:
    body = {"content_type": "image", "media_url": IMG, **extra}
    resp = await client.post("/api/v1/stories/", json=body, headers=auth(token))
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_image_story_keeps_caption(client: AsyncClient):
    token = await register_and_login(client, "sl_cap@test.com", "sl_cap")
    story = await make_story(client, token, text_content="Sparring tonight 🥊")
    assert story["content_type"] == "image"
    assert story["text_content"] == "Sparring tonight 🥊"
    assert story["likes_count"] == 0 and story["liked_by_me"] is False


@pytest.mark.asyncio
async def test_like_toggles_and_counts(client: AsyncClient):
    owner = await register_and_login(client, "sl_o@test.com", "sl_owner")
    fan = await register_and_login(client, "sl_f@test.com", "sl_fan")
    other = await register_and_login(client, "sl_x@test.com", "sl_other")
    story = await make_story(client, owner)
    url = f"/api/v1/stories/{story['id']}/like"

    r1 = await client.post(url, headers=auth(fan))
    assert r1.status_code == 200 and r1.json() == {"liked": True, "likes_count": 1}
    r2 = await client.post(url, headers=auth(other))
    assert r2.json() == {"liked": True, "likes_count": 2}

    # liking twice from the same user = unlike
    r3 = await client.post(url, headers=auth(fan))
    assert r3.json() == {"liked": False, "likes_count": 1}


@pytest.mark.asyncio
async def test_feed_reports_likes_per_viewer(client: AsyncClient):
    owner = await register_and_login(client, "slf_o@test.com", "slf_owner")
    fan = await register_and_login(client, "slf_f@test.com", "slf_fan")
    story = await make_story(client, owner)
    await client.post(f"/api/v1/stories/{story['id']}/like", headers=auth(fan))

    fan_view = (await client.get("/api/v1/stories/feed", headers=auth(fan))).json()
    mine = next(s for s in fan_view if s["id"] == story["id"])
    assert mine["likes_count"] == 1 and mine["liked_by_me"] is True

    owner_view = (await client.get("/api/v1/stories/feed", headers=auth(owner))).json()
    theirs = next(s for s in owner_view if s["id"] == story["id"])
    assert theirs["likes_count"] == 1 and theirs["liked_by_me"] is False


@pytest.mark.asyncio
async def test_like_missing_story_404(client: AsyncClient):
    token = await register_and_login(client, "sl_404@test.com", "sl_404")
    resp = await client.post("/api/v1/stories/99999/like", headers=auth(token))
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_like_followers_only_story_requires_follow(client: AsyncClient):
    owner = await register_and_login(client, "slv_o@test.com", "slv_owner")
    stranger = await register_and_login(client, "slv_s@test.com", "slv_stranger")
    follower = await register_and_login(client, "slv_f@test.com", "slv_follower")
    story = await make_story(client, owner, visibility="followers")
    owner_id = await user_id(client, owner)
    await client.post(f"/api/v1/users/{owner_id}/follow", headers=auth(follower))

    denied = await client.post(f"/api/v1/stories/{story['id']}/like", headers=auth(stranger))
    assert denied.status_code == 403
    allowed = await client.post(f"/api/v1/stories/{story['id']}/like", headers=auth(follower))
    assert allowed.status_code == 200 and allowed.json()["liked"] is True


@pytest.mark.asyncio
async def test_deleting_a_liked_story_cascades(client: AsyncClient):
    owner = await register_and_login(client, "sld_o@test.com", "sld_owner")
    fan = await register_and_login(client, "sld_f@test.com", "sld_fan")
    story = await make_story(client, owner)
    await client.post(f"/api/v1/stories/{story['id']}/like", headers=auth(fan))

    deleted = await client.delete(f"/api/v1/stories/{story['id']}", headers=auth(owner))
    assert deleted.status_code == 204
    gone = await client.post(f"/api/v1/stories/{story['id']}/like", headers=auth(fan))
    assert gone.status_code == 404
