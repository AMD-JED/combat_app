"""
نماذج دعم تعدد الرياضات.

- Sport: قائمة الرياضات المتاحة في المنصة (combat, running, football...).
- UserSportProfile: يربط مستخدمًا برياضة معينة، ويخزّن الحقول الخاصة
  بتلك الرياضة داخل عمود attributes (JSON مرن، لكن يُتحقق منه بصرامة
  عبر Pydantic في app/schemas/sport.py قبل أي كتابة لقاعدة البيانات).

ملاحظة توافق: نستخدم JSONB في PostgreSQL و JSON عادي في SQLite
(بيئة التطوير المحلية كما هو موثق في walkthrough.md) عبر with_variant.
"""
from sqlalchemy import (
    Column,
    Integer,
    String,
    Boolean,
    ForeignKey,
    DateTime,
    JSON,
    func,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import relationship

from app.core.database import Base

# JSONB على PostgreSQL، JSON عادي على SQLite (للتطوير المحلي)
FlexibleJSON = JSONB().with_variant(JSON(), "sqlite")


class Sport(Base):
    """رياضة متاحة على المنصة (combat, running, football...)."""

    __tablename__ = "sports"

    id = Column(Integer, primary_key=True, index=True)
    slug = Column(String(30), unique=True, index=True, nullable=False)
    name = Column(String(50), nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())

    profiles = relationship(
        "UserSportProfile", back_populates="sport", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<Sport {self.slug}>"


class UserSportProfile(Base):
    """
    ملف رياضي واحد لمستخدم معين ضمن رياضة معينة.
    مستخدم واحد يمكن أن يملك عدة صفوف (رياضة قتالية + جري مثلاً)،
    لكن صفًا واحدًا فقط لكل (user_id, sport_id).
    """

    __tablename__ = "user_sport_profiles"
    __table_args__ = (
        UniqueConstraint("user_id", "sport_id", name="uq_user_sport"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    sport_id = Column(
        Integer, ForeignKey("sports.id", ondelete="RESTRICT"), nullable=False, index=True
    )
    is_primary = Column(Boolean, default=False, nullable=False)
    attributes = Column(FlexibleJSON, nullable=False, default=dict)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    user = relationship("User", back_populates="sport_profiles")
    sport = relationship("Sport", back_populates="profiles")

    def __repr__(self) -> str:
        return f"<UserSportProfile user={self.user_id} sport={self.sport_id}>"
