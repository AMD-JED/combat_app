"""Tests for v8 AI Coach. Gemini is mocked — these tests never hit the
real API, so they run without a GEMINI_API_KEY and don't cost quota."""
import pytest
import pytest_asyncio
from httpx import AsyncClient

from app.services import gemini_service


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


@pytest_asyncio.fixture(autouse=True)
async def mock_gemini(monkeypatch):
    """Replace the real provider call with a canned async reply."""
    async def fake_generate_coach_reply(system_context, history, user_message):
        return f"رد تجريبي على: {user_message}"

    monkeypatch.setattr(gemini_service, "generate_coach_reply", fake_generate_coach_reply)
    yield


@pytest.mark.asyncio
async def test_chat_creates_conversation_when_none_given(client: AsyncClient):
    token = await register_and_login(client, "coachuser@test.com", "coach_user")
    resp = await client.post(
        "/api/v1/ai-coach/chat",
        json={"message": "كيف أحسّن الجاب بتاعي؟"},
        headers=auth_headers(token),
    )
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["conversation_id"] is not None
    assert data["user_message"]["role"] == "user"
    assert data["user_message"]["content"] == "كيف أحسّن الجاب بتاعي؟"
    assert data["assistant_message"]["role"] == "assistant"
    assert "رد تجريبي" in data["assistant_message"]["content"]


@pytest.mark.asyncio
async def test_chat_reuses_existing_conversation(client: AsyncClient):
    token = await register_and_login(client, "reuse@test.com", "reuse_user")
    first = await client.post(
        "/api/v1/ai-coach/chat",
        json={"message": "سؤال أول"},
        headers=auth_headers(token),
    )
    conv_id = first.json()["conversation_id"]

    second = await client.post(
        "/api/v1/ai-coach/chat",
        json={"conversation_id": conv_id, "message": "سؤال ثاني"},
        headers=auth_headers(token),
    )
    assert second.status_code == 200
    assert second.json()["conversation_id"] == conv_id

    detail = await client.get(
        f"/api/v1/ai-coach/conversations/{conv_id}", headers=auth_headers(token)
    )
    assert detail.status_code == 200
    # 2 user messages + 2 assistant replies
    assert len(detail.json()["messages"]) == 4


@pytest.mark.asyncio
async def test_cannot_chat_in_other_users_conversation(client: AsyncClient):
    token_a = await register_and_login(client, "convowner@test.com", "convowner")
    token_b = await register_and_login(client, "convintruder@test.com", "convintruder")

    first = await client.post(
        "/api/v1/ai-coach/chat", json={"message": "hi"}, headers=auth_headers(token_a)
    )
    conv_id = first.json()["conversation_id"]

    resp = await client.post(
        "/api/v1/ai-coach/chat",
        json={"conversation_id": conv_id, "message": "trying to intrude"},
        headers=auth_headers(token_b),
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_list_conversations(client: AsyncClient):
    token = await register_and_login(client, "lister@test.com", "lister_user")
    await client.post("/api/v1/ai-coach/chat", json={"message": "one"}, headers=auth_headers(token))
    await client.post("/api/v1/ai-coach/chat", json={"message": "two"}, headers=auth_headers(token))

    resp = await client.get("/api/v1/ai-coach/conversations", headers=auth_headers(token))
    assert resp.status_code == 200
    assert len(resp.json()) == 2


@pytest.mark.asyncio
async def test_chat_returns_503_when_provider_misconfigured(client: AsyncClient, monkeypatch):
    """If the real service raises RuntimeError (e.g. missing API key),
    the endpoint should surface a clean 503 rather than a 500 crash."""
    async def raise_runtime_error(system_context, history, user_message):
        raise RuntimeError("GEMINI_API_KEY is not set.")

    monkeypatch.setattr(gemini_service, "generate_coach_reply", raise_runtime_error)

    token = await register_and_login(client, "noapikey@test.com", "noapikey_user")
    resp = await client.post(
        "/api/v1/ai-coach/chat", json={"message": "hello"}, headers=auth_headers(token)
    )
    assert resp.status_code == 503
