"""Tests for the posts endpoints the Athletes Hub post card depends on:
GET /posts/{id}/comments (new), plus regression guards for the media_url
persistence fix and the reaction fields the Flutter feed reads."""
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


async def create_post(client: AsyncClient, token: str, **payload) -> dict:
    payload = payload or {"content": "hello"}
    resp = await client.post("/api/v1/posts/", json=payload, headers=auth_headers(token))
    assert resp.status_code == 201, resp.text
    return resp.json()


async def add_comment(client: AsyncClient, token: str, post_id: int, content: str):
    resp = await client.post(
        f"/api/v1/posts/{post_id}/comments",
        json={"content": content},
        headers=auth_headers(token),
    )
    assert resp.status_code == 201, resp.text
    return resp.json()


@pytest.mark.asyncio
async def test_get_comments_empty_list_for_new_post(client: AsyncClient):
    token = await register_and_login(client, "c_empty@test.com", "c_empty")
    post = await create_post(client, token)

    resp = await client.get(f"/api/v1/posts/{post['id']}/comments", headers=auth_headers(token))
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_get_comments_newest_first_with_author(client: AsyncClient):
    author_token = await register_and_login(client, "c_author@test.com", "c_author")
    other_token = await register_and_login(client, "c_other@test.com", "c_other")
    post = await create_post(client, author_token)

    await add_comment(client, author_token, post["id"], "first")
    await add_comment(client, other_token, post["id"], "second")
    await add_comment(client, author_token, post["id"], "third")

    resp = await client.get(f"/api/v1/posts/{post['id']}/comments", headers=auth_headers(other_token))
    assert resp.status_code == 200
    items = resp.json()
    assert [c["content"] for c in items] == ["third", "second", "first"]
    assert items[1]["author"]["username"] == "c_other"
    assert items[0]["author"]["username"] == "c_author"
    assert "created_at" in items[0]


@pytest.mark.asyncio
async def test_get_comments_only_returns_that_posts_comments(client: AsyncClient):
    token = await register_and_login(client, "c_scope@test.com", "c_scope")
    post_a = await create_post(client, token, content="A")
    post_b = await create_post(client, token, content="B")
    await add_comment(client, token, post_a["id"], "on A")
    await add_comment(client, token, post_b["id"], "on B")

    resp = await client.get(f"/api/v1/posts/{post_a['id']}/comments", headers=auth_headers(token))
    assert [c["content"] for c in resp.json()] == ["on A"]


@pytest.mark.asyncio
async def test_get_comments_pagination(client: AsyncClient):
    token = await register_and_login(client, "c_page@test.com", "c_page")
    post = await create_post(client, token)
    for i in range(5):
        await add_comment(client, token, post["id"], f"c{i}")

    first = await client.get(
        f"/api/v1/posts/{post['id']}/comments?skip=0&limit=2", headers=auth_headers(token)
    )
    second = await client.get(
        f"/api/v1/posts/{post['id']}/comments?skip=2&limit=2", headers=auth_headers(token)
    )
    assert [c["content"] for c in first.json()] == ["c4", "c3"]
    assert [c["content"] for c in second.json()] == ["c2", "c1"]


@pytest.mark.asyncio
async def test_get_comments_unknown_post_returns_404(client: AsyncClient):
    token = await register_and_login(client, "c_404@test.com", "c_404")
    resp = await client.get("/api/v1/posts/999999/comments", headers=auth_headers(token))
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_get_comments_requires_auth(client: AsyncClient):
    token = await register_and_login(client, "c_auth@test.com", "c_auth")
    post = await create_post(client, token)
    resp = await client.get(f"/api/v1/posts/{post['id']}/comments")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_create_post_persists_media_url(client: AsyncClient):
    """Regression guard: PostCreate used to silently drop media_url."""
    token = await register_and_login(client, "c_media@test.com", "c_media")
    url = "https://res.cloudinary.com/demo/image/upload/sample.jpg"
    post = await create_post(client, token, content="pic", post_type="image", media_url=url)
    assert post["media_url"] == url

    feed = await client.get("/api/v1/posts/feed", headers=auth_headers(token))
    assert feed.json()[0]["media_url"] == url


@pytest.mark.asyncio
async def test_feed_exposes_reaction_fields_the_flutter_card_reads(client: AsyncClient):
    token = await register_and_login(client, "c_react@test.com", "c_react")
    post = await create_post(client, token)

    # nothing yet
    feed = await client.get("/api/v1/posts/feed", headers=auth_headers(token))
    item = feed.json()[0]
    assert item["user_reaction"] is None
    assert item["is_liked_by_me"] is False
    assert item["reaction_counts"] == {
        "respect": 0, "fire": 0, "strength": 0, "precision": 0, "champion": 0, "sport": 0,
    }

    # react with champion, then switch to sport
    r = await client.post(
        f"/api/v1/posts/{post['id']}/react", json={"reaction_type": "champion"},
        headers=auth_headers(token),
    )
    assert r.json()["action"] == "added"
    r = await client.post(
        f"/api/v1/posts/{post['id']}/react", json={"reaction_type": "sport"},
        headers=auth_headers(token),
    )
    assert r.json()["action"] == "updated"

    item = (await client.get("/api/v1/posts/feed", headers=auth_headers(token))).json()[0]
    assert item["user_reaction"] == "sport"
    assert item["is_liked_by_me"] is True
    assert item["likes_count"] == 1
    assert item["reaction_counts"]["sport"] == 1
    assert item["reaction_counts"]["champion"] == 0

    # same type again toggles off
    r = await client.post(
        f"/api/v1/posts/{post['id']}/react", json={"reaction_type": "sport"},
        headers=auth_headers(token),
    )
    assert r.json()["action"] == "removed"
    item = (await client.get("/api/v1/posts/feed", headers=auth_headers(token))).json()[0]
    assert item["user_reaction"] is None
