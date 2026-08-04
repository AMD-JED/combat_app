"""
Tests for media upload endpoints.
Uses mocking to avoid real Cloudinary calls in CI.
"""
import pytest
import io
from unittest.mock import patch, AsyncMock
from httpx import AsyncClient


MOCK_IMAGE_URL = "https://res.cloudinary.com/demo/image/upload/combat/avatars/user_1.webp"
MOCK_VIDEO_URL = "https://res.cloudinary.com/demo/video/upload/combat/posts/videos/sample.mp4"


def make_fake_image(filename: str = "test.jpg") -> tuple:
    """Create an in-memory fake image file for testing."""
    content = b"\xff\xd8\xff\xe0" + b"\x00" * 100  # minimal JPEG header
    return (filename, io.BytesIO(content), "image/jpeg")


def make_fake_video(filename: str = "test.mp4") -> tuple:
    content = b"\x00\x00\x00\x18ftyp" + b"\x00" * 100  # minimal MP4 header
    return (filename, io.BytesIO(content), "video/mp4")


async def get_auth_token(client: AsyncClient) -> str:
    """Helper: register + login, return access token."""
    await client.post("/api/v1/auth/register", json={
        "email": "uploader@test.com",
        "username": "uploader",
        "full_name": "Upload Tester",
        "password": "testpass123",
        "password_confirm": "testpass123",
    })
    resp = await client.post("/api/v1/auth/login", data={
        "username": "uploader@test.com",
        "password": "testpass123",
    })
    return resp.json()["access_token"]


@pytest.mark.asyncio
async def test_upload_avatar_success(client: AsyncClient):
    with patch("app.api.v1.endpoints.uploads.upload_avatar", new_callable=AsyncMock) as mock_upload:
        mock_upload.return_value = MOCK_IMAGE_URL

        token = await get_auth_token(client)
        name, content, mime = make_fake_image("avatar.jpg")
        response = await client.post(
            "/api/v1/uploads/avatar",
            files={"file": (name, content, mime)},
            headers={"Authorization": f"Bearer {token}"},
        )

    assert response.status_code == 200
    data = response.json()
    assert "avatar_url" in data
    assert data["avatar_url"] == MOCK_IMAGE_URL


@pytest.mark.asyncio
async def test_upload_avatar_requires_auth(client: AsyncClient):
    name, content, mime = make_fake_image()
    response = await client.post(
        "/api/v1/uploads/avatar",
        files={"file": (name, content, mime)},
    )
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_upload_post_image_success(client: AsyncClient):
    with patch("app.api.v1.endpoints.uploads.upload_post_image", new_callable=AsyncMock) as mock_upload:
        mock_upload.return_value = {
            "url": MOCK_IMAGE_URL,
            "public_id": "combat/posts/images/post_new_user_1",
            "width": 1080,
            "height": 1080,
            "thumbnail_url": MOCK_IMAGE_URL,
        }
        token = await get_auth_token(client)
        name, content, mime = make_fake_image("training.jpg")
        response = await client.post(
            "/api/v1/uploads/post/image",
            files={"file": (name, content, mime)},
            headers={"Authorization": f"Bearer {token}"},
        )

    assert response.status_code == 200
    data = response.json()
    assert "url" in data
    assert "thumbnail_url" in data
    assert "public_id" in data


@pytest.mark.asyncio
async def test_upload_exercise_video_requires_coach(client: AsyncClient):
    """Non-coach users should be rejected."""
    token = await get_auth_token(client)
    name, content, mime = make_fake_video()
    response = await client.post(
        "/api/v1/uploads/exercise/video?exercise_name=Box+Jump",
        files={"file": (name, content, mime)},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 403
    assert "coaches" in response.json()["detail"].lower()
