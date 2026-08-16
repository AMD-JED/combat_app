"""
سكربت بذر أولي لجدول sports.
آمن للتشغيل أكثر من مرة (لا يُنشئ تكرارًا لرياضة موجودة).

تشغيل من داخل مجلد combat_app (بعد تفعيل venv):
    python -m scripts.seed_sports
"""
import asyncio

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.sport import Sport

INITIAL_SPORTS = [
    {"slug": "combat", "name": "Combat Sports"},
    {"slug": "running", "name": "Running"},
    {"slug": "football", "name": "Football"},
]


async def seed():
    async with AsyncSessionLocal() as session:
        for entry in INITIAL_SPORTS:
            result = await session.execute(
                select(Sport).where(Sport.slug == entry["slug"])
            )
            if result.scalar_one_or_none():
                print(f"[=] الرياضة '{entry['slug']}' موجودة مسبقًا، تم تجاوزها")
                continue
            session.add(Sport(slug=entry["slug"], name=entry["name"], is_active=True))
            print(f"[+] تمت إضافة الرياضة '{entry['slug']}'")
        await session.commit()
    print("[OK] اكتمل البذر")


if __name__ == "__main__":
    asyncio.run(seed())
