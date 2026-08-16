"""
سكربت ترحيل بيانات لمرة واحدة.

ينقل الحقول القتالية الحالية الموجودة مباشرة في جدول users
(sport_type, weight_class, belt_rank, gym_affiliation, coach_name,
wins, losses, draws) إلى صف UserSportProfile واحد جديد لكل مستخدم
(sport='combat', is_primary=True).

هذا السكربت لا يحذف أو يعدّل أي حقل قديم في users — فقط ينسخ البيانات.
آمن للتشغيل أكثر من مرة (يتجاوز المستخدمين الذين لديهم ملف combat مسبقًا).

المتطلبات قبل التشغيل:
    1. تطبيق alembic migration الذي أنشأ جدولي sports و user_sport_profiles.
    2. تشغيل scripts/seed_sports.py أولًا (أو سيُنشئ هذا السكربت رياضة
       combat تلقائيًا إن لم تكن موجودة).

تشغيل من داخل مجلد combat_app (بعد تفعيل venv):
    python -m scripts.migrate_existing_users_to_sport_profiles
"""
import asyncio

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.sport import Sport, UserSportProfile
from app.models.user import User

COMBAT_SPORT_SLUG = "combat"
COMBAT_SPORT_NAME = "Combat Sports"


async def get_or_create_combat_sport(session) -> Sport:
    result = await session.execute(select(Sport).where(Sport.slug == COMBAT_SPORT_SLUG))
    sport = result.scalar_one_or_none()
    if sport:
        return sport
    sport = Sport(slug=COMBAT_SPORT_SLUG, name=COMBAT_SPORT_NAME, is_active=True)
    session.add(sport)
    await session.flush()
    print(f"[+] تم إنشاء رياضة '{COMBAT_SPORT_SLUG}' (لم تكن موجودة)")
    return sport


async def migrate():
    async with AsyncSessionLocal() as session:
        combat_sport = await get_or_create_combat_sport(session)

        result = await session.execute(select(User))
        users = list(result.scalars().all())
        print(f"[i] تم العثور على {len(users)} مستخدم")

        migrated, skipped = 0, 0

        for user in users:
            existing = await session.execute(
                select(UserSportProfile).where(
                    UserSportProfile.user_id == user.id,
                    UserSportProfile.sport_id == combat_sport.id,
                )
            )
            if existing.scalar_one_or_none():
                skipped += 1
                continue

            attributes = {
                "discipline": user.sport_type.value if user.sport_type else None,
                "belt_rank": user.belt_rank,
                "weight_class": user.weight_class.value if user.weight_class else None,
                "gym_affiliation": user.gym_affiliation,
                "coach_name": user.coach_name,
                "wins": user.wins or 0,
                "losses": user.losses or 0,
                "draws": user.draws or 0,
            }
            # إزالة القيم الفارغة فقط (وليس القيم الرقمية 0)
            attributes = {k: v for k, v in attributes.items() if v is not None}

            profile = UserSportProfile(
                user_id=user.id,
                sport_id=combat_sport.id,
                is_primary=True,
                attributes=attributes,
            )
            session.add(profile)
            migrated += 1

        await session.commit()
        print(f"[OK] تم ترحيل {migrated} مستخدم، تم تجاوز {skipped} (لديهم ملف مسبقًا)")


if __name__ == "__main__":
    asyncio.run(migrate())
