"""Tests for v9 Reels."""
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.sport import Sport


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


async def seed_sport(db_session: AsyncSession, slug: str = "combat") -> int:
    sport = Sport(slug=slug, name="Combat Sports")
    db_session.add(sport)
    await db_session.flush()
    await db_session.refresh(sport)
    return sport.id


@pytest.mark.asyncio
async def test_anyone_can_create_reel_non_coach(client: AsyncClient):
    token = await register_and_login(client, "reeler@test.com", "reeler")
    resp = await client.post(
        "/api/v1/reels/",
        json={"media_url": "https://cdn.example.com/reel1.mp4", "caption": "1-2 combo drill"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    data = resp.json()
    assert data["caption"] == "1-2 combo drill"
    assert data["is_coach_content"] is False
    assert data["likes_count"] == 0
    assert data["comments_count"] == 0


@pytest.mark.asyncio
async def test_reel_feed_filtered_by_sport(client: AsyncClient, db_session: AsyncSession):
    combat_id = await seed_sport(db_session, "combat")
    running_id = await seed_sport(db_session, "running")

    token = await register_and_login(client, "sportfilter@test.com", "sport_filter")
    await client.post(
        "/api/v1/reels/",
        json={"media_url": "https://cdn.example.com/combat.mp4", "sport_id": combat_id},
        headers=auth_headers(token),
    )
    await client.post(
        "/api/v1/reels/",
        json={"media_url": "https://cdn.example.com/running.mp4", "sport_id": running_id},
        headers=auth_headers(token),
    )

    resp = await client.get("/api/v1/reels/feed", params={"sport_id": combat_id}, headers=auth_headers(token))
    assert resp.status_code == 200
    reels = resp.json()
    assert len(reels) == 1
    assert reels[0]["sport_id"] == combat_id


@pytest.mark.asyncio
async def test_reel_view_increments_view_count(client: AsyncClient):
    token = await register_and_login(client, "viewsreel@test.com", "views_reel")
    create_resp = await client.post(
        "/api/v1/reels/",
        json={"media_url": "https://cdn.example.com/views.mp4"},
        headers=auth_headers(token),
    )
    reel_id = create_resp.json()["id"]
    assert create_resp.json()["view_count"] == 0

    get_resp = await client.get(f"/api/v1/reels/{reel_id}", headers=auth_headers(token))
    assert get_resp.json()["view_count"] == 1

    get_resp_2 = await client.get(f"/api/v1/reels/{reel_id}", headers=auth_headers(token))
    assert get_resp_2.json()["view_count"] == 2


@pytest.mark.asyncio
async def test_reel_simple_like_toggle_not_six_reactions(client: AsyncClient):
    token = await register_and_login(client, "likereel@test.com", "like_reel")
    create_resp = await client.post(
        "/api/v1/reels/",
        json={"media_url": "https://cdn.example.com/like.mp4"},
        headers=auth_headers(token),
    )
    reel_id = create_resp.json()["id"]

    like_resp = await client.post(f"/api/v1/reels/{reel_id}/like", headers=auth_headers(token))
    assert like_resp.status_code == 200
    assert like_resp.json()["action"] == "liked"

    unlike_resp = await client.post(f"/api/v1/reels/{reel_id}/like", headers=auth_headers(token))
    assert unlike_resp.json()["action"] == "unliked"


@pytest.mark.asyncio
async def test_reel_comments_share_comment_model_with_posts(client: AsyncClient):
    author_token = await register_and_login(client, "reelauthor@test.com", "reel_author")
    commenter_token = await register_and_login(client, "reelcommenter@test.com", "reel_commenter")

    create_resp = await client.post(
        "/api/v1/reels/",
        json={"media_url": "https://cdn.example.com/comment.mp4"},
        headers=auth_headers(author_token),
    )
    reel_id = create_resp.json()["id"]

    comment_resp = await client.post(
        f"/api/v1/reels/{reel_id}/comments",
        json={"content": "Nice technique!"},
        headers=auth_headers(commenter_token),
    )
    assert comment_resp.status_code == 201, comment_resp.text
    assert comment_resp.json()["content"] == "Nice technique!"

    list_resp = await client.get(f"/api/v1/reels/{reel_id}/comments", headers=auth_headers(author_token))
    assert list_resp.status_code == 200
    assert len(list_resp.json()) == 1

    reel_get = await client.get(f"/api/v1/reels/{reel_id}", headers=auth_headers(author_token))
    assert reel_get.json()["comments_count"] == 1


@pytest.mark.asyncio
async def test_coach_reel_shows_badge(client: AsyncClient, db_session: AsyncSession):
    from app.models.user import User
    from sqlalchemy import select

    token = await register_and_login(client, "coachreel@test.com", "coach_reeler")

    result = await db_session.execute(select(User).where(User.username == "coach_reeler"))
    user = result.scalar_one()
    user.is_coach = True
    await db_session.flush()

    resp = await client.post(
        "/api/v1/reels/",
        json={"media_url": "https://cdn.example.com/coach.mp4"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    assert resp.json()["is_coach_content"] is True


@pytest.mark.asyncio
async def test_only_author_can_delete_reel(client: AsyncClient):
    author_token = await register_and_login(client, "delauthor@test.com", "del_author")
    other_token = await register_and_login(client, "delother@test.com", "del_other")

    create_resp = await client.post(
        "/api/v1/reels/",
        json={"media_url": "https://cdn.example.com/del.mp4"},
        headers=auth_headers(author_token),
    )
    reel_id = create_resp.json()["id"]

    forbidden = await client.delete(f"/api/v1/reels/{reel_id}", headers=auth_headers(other_token))
    assert forbidden.status_code == 403

    ok = await client.delete(f"/api/v1/reels/{reel_id}", headers=auth_headers(author_token))
    assert ok.status_code == 204
