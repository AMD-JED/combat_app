import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_register_user(client: AsyncClient):
    response = await client.post("/api/v1/auth/register", json={
        "email": "fighter@test.com",
        "username": "ironmike",
        "full_name": "Mike Tyson",
        "password": "strongpass123",
        "password_confirm": "strongpass123",
    })
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == "fighter@test.com"
    assert data["username"] == "ironmike"


@pytest.mark.asyncio
async def test_register_password_mismatch(client: AsyncClient):
    response = await client.post("/api/v1/auth/register", json={
        "email": "test@test.com",
        "username": "testuser",
        "full_name": "Test User",
        "password": "pass12345",
        "password_confirm": "different",
    })
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_login_success(client: AsyncClient):
    await client.post("/api/v1/auth/register", json={
        "email": "login@test.com",
        "username": "loginuser",
        "full_name": "Login User",
        "password": "testpass123",
        "password_confirm": "testpass123",
    })
    response = await client.post("/api/v1/auth/login", data={
        "username": "login@test.com",
        "password": "testpass123",
    })
    assert response.status_code == 200
    assert "access_token" in response.json()
    assert "refresh_token" in response.json()


@pytest.mark.asyncio
async def test_login_wrong_password(client: AsyncClient):
    await client.post("/api/v1/auth/register", json={
        "email": "wrongpass@test.com",
        "username": "wrongpassuser",
        "full_name": "Wrong Pass User",
        "password": "correctpass123",
        "password_confirm": "correctpass123",
    })
    response = await client.post("/api/v1/auth/login", data={
        "username": "wrongpass@test.com",
        "password": "incorrectpass456",
    })
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_register_duplicate_email(client: AsyncClient):
    await client.post("/api/v1/auth/register", json={
        "email": "duplicate@test.com",
        "username": "firstuser",
        "full_name": "First User",
        "password": "testpass123",
        "password_confirm": "testpass123",
    })
    response = await client.post("/api/v1/auth/register", json={
        "email": "duplicate@test.com",
        "username": "seconduser",
        "full_name": "Second User",
        "password": "testpass456",
        "password_confirm": "testpass456",
    })
    assert response.status_code == 400



@pytest.mark.asyncio
async def test_logout_success(client: AsyncClient):
    # تسجيل مستخدم جديد
    await client.post("/api/v1/auth/register", json={
        "email": "logout@test.com",
        "username": "logoutuser",
        "full_name": "Logout User",
        "password": "logoutpass123",
        "password_confirm": "logoutpass123",
    })

    # تسجيل الدخول للحصول على access_token
    login_response = await client.post("/api/v1/auth/login", data={
        "username": "logout@test.com",
        "password": "logoutpass123",
    })
    access_token = login_response.json()["access_token"]
    headers = {"Authorization": f"Bearer {access_token}"}

    # التأكد أن التوكن صالح قبل تسجيل الخروج
    me_response = await client.get("/api/v1/auth/me", headers=headers)
    assert me_response.status_code == 200

    # تنفيذ تسجيل الخروج
    logout_response = await client.post("/api/v1/auth/logout", headers=headers)
    assert logout_response.status_code == 200
    assert logout_response.json()["detail"] == "Successfully logged out"

    # التأكد أن نفس التوكن أصبح مرفوضًا الآن
    me_after_logout = await client.get("/api/v1/auth/me", headers=headers)
    assert me_after_logout.status_code == 401


@pytest.mark.asyncio
async def test_logout_requires_auth(client: AsyncClient):
    response = await client.post("/api/v1/auth/logout")
    assert response.status_code == 401