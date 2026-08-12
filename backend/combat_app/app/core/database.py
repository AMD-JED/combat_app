from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase
from app.core.config import settings

# Detect SQLite vs PostgreSQL to adjust engine options
_is_sqlite = settings.DATABASE_URL.startswith("sqlite")

_engine_kwargs = {
    "echo": settings.DEBUG,
}

if not _is_sqlite:
    # PostgreSQL pool options (not supported by SQLite)
    _engine_kwargs.update({
        "pool_pre_ping": True,
        "pool_size": 10,
        "max_overflow": 20,
    })

if _is_sqlite:
    # SQLite needs connect_args for async usage
    _engine_kwargs["connect_args"] = {"check_same_thread": False}

# Async engine
engine = create_async_engine(
    settings.DATABASE_URL,
    **_engine_kwargs,
)

# Session factory
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
    autocommit=False,
)


class Base(DeclarativeBase):
    pass


# ──────────────────────────────────────────────
#  Dependency for FastAPI routes
# ──────────────────────────────────────────────

async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()
