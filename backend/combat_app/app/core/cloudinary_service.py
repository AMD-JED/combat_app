"""
Cloudinary Service
==================
Handles all media uploads for Combat Sports Network.

Supported:
  - Avatar images     → folder: combat/avatars/
  - Post images       → folder: combat/posts/images/
  - Post videos       → folder: combat/posts/videos/
  - Exercise thumbnails → folder: combat/exercises/thumbnails/
  - Exercise videos   → folder: combat/exercises/videos/

Features:
  - Auto image optimization (quality, format)
  - Video transcoding to HLS-ready MP4
  - File type validation (MIME check)
  - Max file size enforcement
  - Old media cleanup on update
"""

import uuid
from typing import Optional
from enum import Enum

import cloudinary
import cloudinary.uploader
import cloudinary.api
from fastapi import UploadFile, HTTPException, status

from app.core.config import settings

# ──────────────────────────────────────────────
#  Configure Cloudinary once on import
# ──────────────────────────────────────────────
cloudinary.config(
    cloud_name=settings.CLOUDINARY_CLOUD_NAME,
    api_key=settings.CLOUDINARY_API_KEY,
    api_secret=settings.CLOUDINARY_API_SECRET,
    secure=True,
)

# ──────────────────────────────────────────────
#  Constants
# ──────────────────────────────────────────────

MAX_IMAGE_SIZE = 10 * 1024 * 1024   # 10 MB
MAX_VIDEO_SIZE = 200 * 1024 * 1024  # 200 MB

ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
ALLOWED_VIDEO_TYPES = {"video/mp4", "video/quicktime", "video/x-msvideo", "video/webm"}


class UploadFolder(str, Enum):
    AVATAR          = "combat/avatars"
    POST_IMAGE      = "combat/posts/images"
    POST_VIDEO      = "combat/posts/videos"
    EXERCISE_THUMB  = "combat/exercises/thumbnails"
    EXERCISE_VIDEO  = "combat/exercises/videos"

    def __str__(self):
        return self.value


# ──────────────────────────────────────────────
#  Internal helpers
# ──────────────────────────────────────────────

def _validate_image(file: UploadFile, max_size: int = MAX_IMAGE_SIZE) -> None:
    if file.content_type not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Image type '{file.content_type}' not allowed. Use: JPEG, PNG, WEBP, GIF",
        )


def _validate_video(file: UploadFile, max_size: int = MAX_VIDEO_SIZE) -> None:
    if file.content_type not in ALLOWED_VIDEO_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail=f"Video type '{file.content_type}' not allowed. Use: MP4, MOV, AVI, WEBM",
        )


async def _read_file(file: UploadFile, max_size: int = 0) -> bytes:
    contents = await file.read()
    await file.seek(0)
    if max_size and len(contents) > max_size:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File too large. Max size: {max_size // (1024*1024)} MB",
        )
    return contents


# ──────────────────────────────────────────────
#  Public Upload Functions
# ──────────────────────────────────────────────

async def upload_avatar(file: UploadFile, user_id: int) -> str:
    """
    Upload user avatar. Auto-crops to face, converts to WebP.
    Returns: secure URL string
    """
    _validate_image(file)
    contents = await _read_file(file, max_size=MAX_IMAGE_SIZE)

    try:
        result = cloudinary.uploader.upload(
            contents,
            public_id=f"{UploadFolder.AVATAR.value}/user_{user_id}",
            overwrite=True,                    # Replaces old avatar automatically
            resource_type="image",
            transformation=[
                {
                    "width": 400,
                    "height": 400,
                    "crop": "fill",
                    "gravity": "face",         # Smart face detection crop
                    "quality": "auto:good",
                    "fetch_format": "webp",    # Auto convert to WebP
                }
            ],
        )
        return result["secure_url"]

    except cloudinary.exceptions.Error as e:
        raise HTTPException(status_code=500, detail=f"Avatar upload failed: {str(e)}")


async def upload_post_image(file: UploadFile, user_id: int, post_id: Optional[int] = None) -> dict:
    """
    Upload post image. Auto-optimizes quality and format.
    Returns: {"url": str, "public_id": str, "width": int, "height": int}
    """
    _validate_image(file)
    contents = await _read_file(file, max_size=MAX_IMAGE_SIZE)

    public_id = f"{UploadFolder.POST_IMAGE.value}/post_{post_id or 'new'}_user_{user_id}"

    try:
        result = cloudinary.uploader.upload(
            contents,
            public_id=public_id,
            resource_type="image",
            transformation=[
                {
                    "width": 1080,
                    "height": 1080,
                    "crop": "limit",           # Don't upscale, only downscale
                    "quality": "auto:best",
                    "fetch_format": "auto",    # WebP for browsers that support it
                }
            ],
            eager=[
                # Generate thumbnail for feed preview
                {
                    "width": 400,
                    "height": 400,
                    "crop": "fill",
                    "quality": "auto:eco",
                    "fetch_format": "webp",
                }
            ],
            eager_async=True,
        )
        return {
            "url": result["secure_url"],
            "public_id": result["public_id"],
            "width": result.get("width"),
            "height": result.get("height"),
            "thumbnail_url": result["eager"][0]["secure_url"] if result.get("eager") else result["secure_url"],
        }

    except cloudinary.exceptions.Error as e:
        raise HTTPException(status_code=500, detail=f"Image upload failed: {str(e)}")


async def upload_post_video(file: UploadFile, user_id: int) -> dict:
    """
    Upload post video. Transcodes to MP4, generates thumbnail.
    Returns: {"url": str, "public_id": str, "thumbnail_url": str, "duration": float}
    """
    _validate_video(file)
    contents = await _read_file(file, max_size=MAX_VIDEO_SIZE)

    unique_id = uuid.uuid4().hex[:12]
    public_id = f"{UploadFolder.POST_VIDEO.value}/video_{unique_id}_user_{user_id}"

    try:
        result = cloudinary.uploader.upload(
            contents,
            public_id=public_id,
            resource_type="video",
            chunk_size=6_000_000,
            eager=[
                {
                    "format": "mp4",
                    "transformation": [
                        {"quality": "auto:good", "video_codec": "h264"},
                    ],
                },
                {
                    "format": "jpg",
                    "transformation": [
                        {"width": 640, "height": 360, "crop": "fill", "start_offset": "1"},
                    ],
                },
            ],
            eager_async=True,
            notification_url=None,
        )

        thumbnail_url = None
        if result.get("eager") and len(result["eager"]) > 1:
            thumbnail_url = result["eager"][1]["secure_url"]

        return {
            "url": result["secure_url"],
            "public_id": result["public_id"],
            "thumbnail_url": thumbnail_url,
            "duration": result.get("duration"),
            "width": result.get("width"),
            "height": result.get("height"),
        }

    except cloudinary.exceptions.Error as e:
        raise HTTPException(status_code=500, detail=f"Video upload failed: {str(e)}")


async def upload_exercise_video(file: UploadFile, exercise_name: str) -> dict:
    """
    Upload exercise tutorial video.
    Returns: {"url": str, "public_id": str, "thumbnail_url": str}
    """
    _validate_video(file)
    contents = await _read_file(file, max_size=MAX_VIDEO_SIZE)

    safe_name = exercise_name.lower().replace(" ", "_")

    try:
        result = cloudinary.uploader.upload(
            contents,
            public_id=f"{UploadFolder.EXERCISE_VIDEO.value}/{safe_name}",
            resource_type="video",
            overwrite=True,
            eager=[
                # HD version
                {
                    "format": "mp4",
                    "transformation": [
                        {"width": 1280, "height": 720, "crop": "limit", "quality": "auto:good"},
                    ],
                },
                # Thumbnail at 2 seconds (usually mid-movement = clearer)
                {
                    "format": "jpg",
                    "transformation": [
                        {"width": 640, "height": 360, "crop": "fill", "start_offset": "2"},
                    ],
                },
            ],
            eager_async=True,
        )

        thumbnail_url = None
        if result.get("eager") and len(result["eager"]) > 1:
            thumbnail_url = result["eager"][1]["secure_url"]

        return {
            "url": result["secure_url"],
            "public_id": result["public_id"],
            "thumbnail_url": thumbnail_url,
        }

    except cloudinary.exceptions.Error as e:
        raise HTTPException(status_code=500, detail=f"Exercise video upload failed: {str(e)}")


# ──────────────────────────────────────────────
#  Delete
# ──────────────────────────────────────────────

def delete_media(public_id: str, resource_type: str = "image") -> bool:
    """
    Delete a media file from Cloudinary by its public_id.
    Called when user deletes a post or updates avatar.
    """
    try:
        result = cloudinary.uploader.destroy(public_id, resource_type=resource_type)
        return result.get("result") == "ok"
    except cloudinary.exceptions.Error:
        return False  # Log but don't crash — orphaned files are non-critical
