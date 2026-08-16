"""
Pydantic schemas لدعم تعدد الرياضات.

التحقق صارم لكل رياضة: كل رياضة لها نموذج Pydantic خاص بحقولها
(extra="forbid" يمنع أي حقل غير معرّف)، ومسجّلة في SPORT_ATTRIBUTE_SCHEMAS.

لإضافة رياضة جديدة مستقبلًا:
  1. أنشئ صف جديد في جدول sports (slug + name).
  2. أنشئ class جديد هنا يرث من SportAttributesBase بحقول تلك الرياضة.
  3. أضفه إلى SPORT_ATTRIBUTE_SCHEMAS بنفس الـ slug.
"""
from datetime import datetime
from typing import Any, ClassVar, Dict, Optional, Type

from pydantic import BaseModel, Field, model_validator

from app.models.user import SportType, WeightClass

# ────────────────────────────────────────────────
# Base
# ────────────────────────────────────────────────


class SportAttributesBase(BaseModel):
    """كل نموذج attributes خاص برياضة يجب أن يرث من هذا الصنف."""

    model_config = {"extra": "forbid"}


# ────────────────────────────────────────────────
# نماذج الحقول الخاصة بكل رياضة (تحقق صارم)
# ────────────────────────────────────────────────


class CombatAttributes(SportAttributesBase):
    """
    حقول الرياضات القتالية — تطابق الحقول القديمة التي كانت
    مباشرة في User (sport_type, weight_class, belt_rank...).
    """

    discipline: Optional[SportType] = None
    belt_rank: Optional[str] = Field(None, max_length=50)
    weight_class: Optional[WeightClass] = None
    stance: Optional[str] = Field(None, max_length=20)
    gym_affiliation: Optional[str] = Field(None, max_length=100)
    coach_name: Optional[str] = Field(None, max_length=100)
    wins: int = Field(0, ge=0)
    losses: int = Field(0, ge=0)
    draws: int = Field(0, ge=0)


class RunningAttributes(SportAttributesBase):
    preferred_terrain: Optional[str] = Field(None, max_length=30)
    weekly_goal_km: Optional[float] = Field(None, ge=0, le=500)
    personal_best_5k_seconds: Optional[int] = Field(None, ge=0)
    personal_best_10k_seconds: Optional[int] = Field(None, ge=0)
    personal_best_marathon_seconds: Optional[int] = Field(None, ge=0)


class FootballAttributes(SportAttributesBase):
    position: Optional[str] = Field(None, max_length=30)
    preferred_foot: Optional[str] = Field(None, pattern=r"^(Left|Right|Both)$")
    club_affiliation: Optional[str] = Field(None, max_length=100)


# ────────────────────────────────────────────────
# السجل المركزي: slug الرياضة -> نموذج التحقق
# ────────────────────────────────────────────────

SPORT_ATTRIBUTE_SCHEMAS: Dict[str, Type[SportAttributesBase]] = {
    "combat": CombatAttributes,
    "running": RunningAttributes,
    "football": FootballAttributes,
}


def validate_sport_attributes(sport_slug: str, raw_attributes: dict) -> dict:
    """
    يتحقق من raw_attributes مقابل النموذج المسجَّل لهذه الرياضة.
    يرفع ValueError (يتحول تلقائيًا إلى 422 من طرف FastAPI عبر model_validator)
    إن كانت الرياضة غير مسجَّلة أو كانت البيانات غير صالحة.
    """
    schema_cls = SPORT_ATTRIBUTE_SCHEMAS.get(sport_slug)
    if schema_cls is None:
        raise ValueError(
            f"لا يوجد نموذج تحقق مسجَّل للرياضة '{sport_slug}'. "
            f"أضف واحدًا في SPORT_ATTRIBUTE_SCHEMAS داخل app/schemas/sport.py."
        )
    validated = schema_cls(**raw_attributes)
    return validated.model_dump(exclude_none=True)


# ────────────────────────────────────────────────
# Sport (قراءة فقط)
# ────────────────────────────────────────────────


class SportResponse(BaseModel):
    id: int
    slug: str
    name: str
    is_active: bool

    model_config = {"from_attributes": True}


# ────────────────────────────────────────────────
# UserSportProfile — إنشاء / تعديل / استجابة
# ────────────────────────────────────────────────


class UserSportProfileCreate(BaseModel):
    sport_slug: str = Field(..., description="مثال: combat, running, football")
    is_primary: bool = False
    attributes: Dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def _validate_attributes(self) -> "UserSportProfileCreate":
        self.attributes = validate_sport_attributes(self.sport_slug, self.attributes)
        return self


class UserSportProfileUpdate(BaseModel):
    """
    ملاحظة: لا يمكن تغيير sport_slug هنا عمدًا — تغيير رياضة الملف
    يعني حذف الملف القديم وإنشاء ملف جديد (create_for_user) لتفادي
    اختلاط attributes بين نموذجين تحقق مختلفين.
    """

    is_primary: Optional[bool] = None
    attributes: Optional[Dict[str, Any]] = None


class UserSportProfileResponse(BaseModel):
    id: int
    sport: SportResponse
    is_primary: bool
    attributes: Dict[str, Any]
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
