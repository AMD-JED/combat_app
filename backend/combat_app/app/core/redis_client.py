import redis.asyncio as redis
from app.core.config import settings

redis_client = redis.from_url(settings.REDIS_URL, decode_responses=True)


async def blacklist_token(jti: str, expires_in_seconds: int) -> None:
    """يضيف الـ JTI إلى القائمة السوداء حتى انتهاء صلاحية التوكن الأصلي."""
    if expires_in_seconds > 0:
        await redis_client.setex(f"blacklist:{jti}", expires_in_seconds, "true")


async def is_token_blacklisted(jti: str) -> bool:
    """يتحقق إن كان التوكن ضمن القائمة السوداء."""
    result = await redis_client.get(f"blacklist:{jti}")
    return result is not None