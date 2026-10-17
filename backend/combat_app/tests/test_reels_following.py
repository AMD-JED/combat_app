"""v12 — `is_following_author` on reels (feed + single reel)."""
import pytest
from httpx import AsyncClient

from tests.test_reels import auth_headers, register_and_login


async def _me_id(client: AsyncClient, token: str) -> int:
    resp = await client.get("/api/v1/auth/me", headers=auth_headers(token))
    return resp.json()["id"]


async def _post_reel(client: AsyncClient, token: str, name: str) -> int:
    resp = await client.post(
        "/api/v1/reels/",
        json={"media_url": f"https://cdn.example.com/{name}.mp4"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["id"]


@pytest.mark.asyncio
async def test_feed_flags_followed_authors_only(client: AsyncClient):
    author_a = await register_and_login(client, "fa@test.com", "follow_a")
    author_b = await register_and_login(client, "fb@test.com", "follow_b")
    viewer = await register_and_login(client, "fv@test.com", "follow_viewer")

    reel_a = await _post_reel(client, author_a, "a")
    reel_b = await _post_reel(client, author_b, "b")

    # Nobody followed yet.
    feed = (await client.get("/api/v1/reels/feed", headers=auth_headers(viewer))).json()
    assert {r["id"]: r["is_following_author"] for r in feed} == {reel_a: False, reel_b: False}

    # Follow A only.
    a_id = await _me_id(client, author_a)
    follow = await client.post(f"/api/v1/users/{a_id}/follow", headers=auth_headers(viewer))
    assert follow.json()["action"] == "followed"

    feed = (await client.get("/api/v1/reels/feed", headers=auth_headers(viewer))).json()
    assert {r["id"]: r["is_following_author"] for r in feed} == {reel_a: True, reel_b: False}

    # Unfollow flips it back.
    await client.post(f"/api/v1/users/{a_id}/follow", headers=auth_headers(viewer))
    feed = (await client.get("/api/v1/reels/feed", headers=auth_headers(viewer))).json()
    assert all(r["is_following_author"] is False for r in feed)


@pytest.mark.asyncio
async def test_own_reels_are_never_flagged(client: AsyncClient):
    token = await register_and_login(client, "fown@test.com", "follow_own")
    reel_id = await _post_reel(client, token, "own")

    feed = (await client.get("/api/v1/reels/feed", headers=auth_headers(token))).json()
    assert feed[0]["is_following_author"] is False

    single = await client.get(f"/api/v1/reels/{reel_id}", headers=auth_headers(token))
    assert single.json()["is_following_author"] is False


@pytest.mark.asyncio
async def test_single_reel_reports_follow_state(client: AsyncClient):
    author = await register_and_login(client, "fs1@test.com", "follow_single_a")
    viewer = await register_and_login(client, "fs2@test.com", "follow_single_v")
    reel_id = await _post_reel(client, author, "single")

    before = await client.get(f"/api/v1/reels/{reel_id}", headers=auth_headers(viewer))
    assert before.json()["is_following_author"] is False

    await client.post(
        f"/api/v1/users/{await _me_id(client, author)}/follow", headers=auth_headers(viewer)
    )
    after = await client.get(f"/api/v1/reels/{reel_id}", headers=auth_headers(viewer))
    assert after.json()["is_following_author"] is True


@pytest.mark.asyncio
async def test_create_response_defaults_to_not_following(client: AsyncClient):
    token = await register_and_login(client, "fc@test.com", "follow_create")
    resp = await client.post(
        "/api/v1/reels/",
        json={"media_url": "https://cdn.example.com/c.mp4"},
        headers=auth_headers(token),
    )
    assert resp.json()["is_following_author"] is False
