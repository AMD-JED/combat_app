"""
File Validation Utilities
==========================
Validates uploaded files by actual content (magic bytes), not just
filename/extension, and enforces size limits before any file reaches
Cloudinary.
"""

from fastapi import UploadFile, HTTPException
from app.core.config import settings

try:
    import magic
except ImportError:
    magic = None

ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
ALLOWED_VIDEO_TYPES = {"video/mp4", "video/quicktime", "video/x-msvideo", "video/webm"}

# ~2MB is plenty to reliably detect type from the file header
_SNIFF_BYTES = 2 * 1024 * 1024


async def validate_file(
    file: UploadFile,
    allowed_types: set[str],
    max_size_mb: int | None = None,
) -> None:
    """
    Validates both the real content-type (magic bytes) and size of an
    uploaded file. Raises HTTPException on failure. Resets the file
    pointer to 0 afterwards so the caller can read the full file again.
    """
    max_bytes = (max_size_mb or settings.MAX_FILE_SIZE_MB) * 1024 * 1024

    # --- Size check ---
    file.file.seek(0, 2)  # seek to end
    size = file.file.tell()
    file.file.seek(0)  # rewind

    if size == 0:
        raise HTTPException(status_code=400, detail="الملف فارغ")

    if size > max_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"حجم الملف ({size // (1024*1024)}MB) يتجاوز الحد المسموح ({max_bytes // (1024*1024)}MB)",
        )

    # --- Content-type check (magic bytes, not extension) ---
    header = await file.read(_SNIFF_BYTES)
    await file.seek(0)  # rewind for the actual upload later

    if magic is not None:
        try:
            detected_type = magic.from_buffer(header, mime=True)
        except Exception:
            detected_type = file.content_type
    else:
        detected_type = file.content_type

    if detected_type not in allowed_types:
        raise HTTPException(
            status_code=400,
            detail=f"نوع الملف غير مسموح ({detected_type}). الأنواع المسموحة: {', '.join(sorted(allowed_types))}",
        )