"""
Media Upload Endpoints
======================
All file uploads go through here before being attached to posts/profiles.

Flow:
  1. Client uploads file → gets back a URL
  2. Client uses that URL when creating/updating a post or profile

Endpoints:
  POST /uploads/avatar          ← Update current user's avatar
  POST /uploads/post/image      ← Upload image for a post
  POST /uploads/post/video      ← Upload video for a post
  POST /uploads/exercise/video  ← Upload exercise tutorial (coaches only)
  DELETE /uploads/{public_id}   ← Delete a media file
"""

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from app.core.database import get_db
from app.core.dependencies import get_current_active_user
from app.core.cloudinary_service import (
    upload_avatar,
    upload_post_image,
    upload_post_video,
    upload_exercise_video,
    delete_media,
)
from app.core.file_validation import (
    validate_file,
    ALLOWED_IMAGE_TYPES,
    ALLOWED_VIDEO_TYPES,
)
from app.models.user import User
from app.repositories.user_repository import UserRepository

router = APIRouter(prefix="/uploads", tags=["Media Uploads"])


# ──────────────────────────────────────────────
#  Avatar
# ──────────────────────────────────────────────

@router.post("/avatar")
async def update_avatar(
    file: UploadFile = File(..., description="JPEG, PNG, or WEBP image. Max 10MB."),
    current_user: User = Depends(get_current_active_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Upload a new profile picture.
    - Auto-crops to face (400×400)
    - Converts to WebP for fast loading
    - Replaces previous avatar automatically
    """
    await validate_file(file, ALLOWED_IMAGE_TYPES, max_size_mb=10)

    url = await upload_avatar(file, user_id=current_user.id)

    # Save URL to user profile
    repo = UserRepository(db)
    await repo.update(current_user.id, {"avatar_url": url})

    return {
        "message": "Avatar updated successfully",
        "avatar_url": url,
    }


# ──────────────────────────────────────────────
#  Post Media
# ──────────────────────────────────────────────

@router.post("/post/image")
async def upload_image_for_post(
    file: UploadFile = File(..., description="JPEG, PNG, WEBP, or GIF. Max 10MB."),
    post_id: Optional[int] = Query(None, description="Attach to existing post (optional)"),
    current_user: User = Depends(get_current_active_user),
):
    """
    Upload an image to attach to a post.

    Returns URLs for both full-size and thumbnail versions.
    Use the returned `url` when creating the post.
    """
    await validate_file(file, ALLOWED_IMAGE_TYPES, max_size_mb=10)

    result = await upload_post_image(file, user_id=current_user.id, post_id=post_id)
    return {
        "message": "Image uploaded successfully",
        **result,
    }


@router.post("/post/video")
async def upload_video_for_post(
    file: UploadFile = File(..., description="MP4, MOV, AVI, or WEBM. Max 200MB."),
    current_user: User = Depends(get_current_active_user),
):
    """
    Upload a training video to attach to a post.

    - Auto-transcodes to H.264 MP4
    - Generates a thumbnail at the 1-second mark
    - Processing happens async (large files may take a moment)
    """
    await validate_file(file, ALLOWED_VIDEO_TYPES, max_size_mb=200)

    result = await upload_post_video(file, user_id=current_user.id)
    return {
        "message": "Video uploaded successfully",
        **result,
    }


# ──────────────────────────────────────────────
#  Exercise Tutorial
# ──────────────────────────────────────────────

@router.post("/exercise/video")
async def upload_exercise_tutorial(
    file: UploadFile = File(..., description="MP4 or MOV video. Max 200MB."),
    exercise_name: str = Query(..., min_length=2, description="Name of the exercise (used as file ID)"),
    current_user: User = Depends(get_current_active_user),
):
    """
    Upload a tutorial video for an exercise (coaches only).

    - Transcodes to 1280×720 MP4
    - Generates thumbnail at the 2-second mark (typically shows movement)
    """
    if not current_user.is_coach:
        raise HTTPException(status_code=403, detail="Only coaches can upload exercise tutorials")

    await validate_file(file, ALLOWED_VIDEO_TYPES, max_size_mb=200)

    result = await upload_exercise_video(file, exercise_name=exercise_name)
    return {
        "message": "Exercise video uploaded successfully",
        **result,
    }


# ──────────────────────────────────────────────
#  Delete
# ──────────────────────────────────────────────

@router.delete("/{public_id:path}")
async def remove_media(
    public_id: str,
    resource_type: str = Query("image", pattern="^(image|video)$"),
    current_user: User = Depends(get_current_active_user),
):
    """
    Delete a previously uploaded media file.
    Pass the `public_id` returned from any upload endpoint.

    Example: DELETE /uploads/combat/posts/images/post_42_user_7

    Security:
      - Avatars / post images / post videos: only the owner (public_id
        must contain this user's own "user_{id}" segment) may delete.
      - Exercise videos: shared coach library — any authenticated coach
        may delete (no per-user ownership encoded in these public_ids).
    """
    if public_id.startswith("combat/exercises/"):
        if not current_user.is_coach:
            raise HTTPException(
                status_code=403,
                detail="Only coaches can delete exercise media",
            )
    else:
        owner_marker = f"user_{current_user.id}"
        if owner_marker not in public_id:
            raise HTTPException(
                status_code=403,
                detail="You are not allowed to delete this media file",
            )

    success = delete_media(public_id, resource_type=resource_type)
    if not success:
        raise HTTPException(status_code=404, detail="Media not found or already deleted")

    return {"message": "Media deleted successfully", "public_id": public_id}