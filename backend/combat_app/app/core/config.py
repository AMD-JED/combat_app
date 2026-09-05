from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache
from typing import List


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", case_sensitive=True)

    # --- App ---
    APP_NAME: str = "Combat Sports Network"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False

    # --- Database ---
    DATABASE_URL: str

    # --- JWT ---
    SECRET_KEY: str
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # --- OAuth2 (Google) ---
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""

    # --- CORS ---
    ALLOWED_ORIGINS: List[str] = ["http://localhost:3000"]

    # --- Files ---
    MAX_FILE_SIZE_MB: int = 50
    UPLOAD_DIR: str = "uploads"

    # --- Cloudinary ---
    CLOUDINARY_CLOUD_NAME: str = ""
    CLOUDINARY_API_KEY: str = ""
    CLOUDINARY_API_SECRET: str = ""

    # --- Redis ---
    REDIS_URL: str = "redis://localhost:6379"

    # --- AI Coach (v8) ---
    # Empty default so the app still boots without it — the /ai-coach/chat
    # endpoint raises a clear 503 instead of a crash if it's missing.
    # Abstracted behind app/services/gemini_service.py: this is the only
    # place a future provider switch (Claude/OpenAI/Ollama) would touch.
    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-2.5-flash"


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
