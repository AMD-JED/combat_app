import sys
import os
import pytest_asyncio
import pytest
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.pool import StaticPool

# 1. إضافة مسار المشروع لـ sys.path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.main import app, limiter as main_limiter
from app.api.v1.endpoints.auth import limiter as auth_limiter
from app.core.database import Base, get_db

# Disable rate limiting for unit tests
main_limiter.enabled = False
auth_limiter.enabled = False

# 2. إنشاء محرك قاعدة بيانات مؤقتة في الذاكرة (In-Memory SQLite)
TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"

engine_test = create_async_engine(
    TEST_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)

TestingSessionLocal = async_sessionmaker(
    bind=engine_test,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
    autocommit=False,
)

# 3. Fixture لتهيئة وحذف الجداول تلقائياً قبل وبعد كل دالة اختبار
@pytest_asyncio.fixture(scope="function", autouse=True)
async def prepare_database():
    async with engine_test.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with engine_test.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)

# 3b. Mock Redis لتجنب خطأ "Event loop is closed"
#     المشكلة: redis_client يُنشأ مرة واحدة عند الـ import ويُربط بـ event loop معيّن.
#     عند كل اختبار يُنشأ event loop جديد، فيصبح الـ client القديم غير صالح.
#     الحل: استبدال redis_client بـ mock بسيط في الذاكرة لكل اختبار.
@pytest_asyncio.fixture(scope="function", autouse=True)
async def mock_redis(monkeypatch):
    """Replace the real Redis client with an in-memory mock for each test."""
    from unittest.mock import MagicMock
    import app.core.redis_client as redis_module

    fake_store: dict = {}

    mock_client = MagicMock()

    async def fake_get(key):
        return fake_store.get(key)

    async def fake_setex(key, ttl, value):
        fake_store[key] = value

    async def fake_delete(*keys):
        for k in keys:
            fake_store.pop(k, None)

    mock_client.get = fake_get
    mock_client.setex = fake_setex
    mock_client.delete = fake_delete

    monkeypatch.setattr(redis_module, "redis_client", mock_client)
    yield mock_client

# 4. Fixture لتوجيه FastAPI لاستخدام قاعدة بيانات الاختبارات بدلاً من الحقيقية
@pytest_asyncio.fixture
async def client():
    async def override_get_db():
        async with TestingSessionLocal() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    app.dependency_overrides[get_db] = override_get_db

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac

    app.dependency_overrides.clear()
