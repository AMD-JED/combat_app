from sqlalchemy import (
    Column,
    Integer,
    String,
    Boolean,
    Enum,
    Text,
    DateTime,
    func,
    Table,
    ForeignKey,
)
from sqlalchemy.orm import relationship
from app.core.database import Base
import enum


class SportType(str, enum.Enum):
    MMA = "MMA"
    BOXING = "Boxing"
    BJJ = "BJJ"
    MUAY_THAI = "Muay Thai"
    WRESTLING = "Wrestling"
    JUDO = "Judo"
    KARATE = "Karate"
    KICKBOXING = "Kickboxing"
    OTHER = "Other"


class WeightClass(str, enum.Enum):
    STRAWWEIGHT = "Strawweight"  # -115 lbs
    FLYWEIGHT = "Flyweight"  # -125 lbs
    BANTAMWEIGHT = "Bantamweight"  # -135 lbs
    FEATHERWEIGHT = "Featherweight"  # -145 lbs
    LIGHTWEIGHT = "Lightweight"  # -155 lbs
    WELTERWEIGHT = "Welterweight"  # -170 lbs
    MIDDLEWEIGHT = "Middleweight"  # -185 lbs
    LIGHT_HEAVYWEIGHT = "Light Heavyweight"  # -205 lbs
    HEAVYWEIGHT = "Heavyweight"  # -265 lbs


# Association table for followers
follows = Table(
    "follows",
    Base.metadata,
    Column("follower_id", Integer, ForeignKey("users.id"), primary_key=True),
    Column("followed_id", Integer, ForeignKey("users.id"), primary_key=True),
)


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    username = Column(String(50), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=True)  # nullable for OAuth users
    full_name = Column(String(100), nullable=False)

    # Athlete Profile
    # ملاحظة: هذه الحقول تبقى مؤقتًا للتوافق العكسي (deprecated).
    # المصدر الجديد للحقيقة لملفات الرياضات المتعددة هو UserSportProfile.
    sport_type = Column(Enum(SportType), nullable=True)
    weight_class = Column(Enum(WeightClass), nullable=True)
    belt_rank = Column(String(50), nullable=True)  # e.g., "Black Belt", "Blue Belt"
    gym_affiliation = Column(String(100), nullable=True)
    coach_name = Column(String(100), nullable=True)
    bio = Column(Text, nullable=True)
    avatar_url = Column(String(500), nullable=True)
    location = Column(String(100), nullable=True)

    # Fight Record
    wins = Column(Integer, default=0)
    losses = Column(Integer, default=0)
    draws = Column(Integer, default=0)

    # OAuth
    google_id = Column(String(255), unique=True, nullable=True)

    # Flags
    is_active = Column(Boolean, default=True)
    is_verified = Column(Boolean, default=False)
    is_coach = Column(Boolean, default=False)

    # Timestamps
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relationships
    posts = relationship("Post", back_populates="author", cascade="all, delete-orphan")
    followers = relationship(
        "User",
        secondary=follows,
        primaryjoin=id == follows.c.followed_id,
        secondaryjoin=id == follows.c.follower_id,
        back_populates="following",
    )
    following = relationship(
        "User",
        secondary=follows,
        primaryjoin=id == follows.c.follower_id,
        secondaryjoin=id == follows.c.followed_id,
        back_populates="followers",
    )

    # جديد: دعم تعدد الرياضات — مستخدم واحد قد يملك عدة ملفات رياضية
    sport_profiles = relationship(
        "UserSportProfile", back_populates="user", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<User {self.username} | {self.sport_type}>"
