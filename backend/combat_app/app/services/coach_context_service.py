"""
v8 — AI Coach context builder.

Turns real data already in the database (sport profile(s), recent
training sessions, sparring activity) into a compact, plain-text block
that gets injected as the system prompt before calling the AI provider
(see app/services/gemini_service.py). This is what makes AI Coach
replies specific to the athlete instead of generic — the provider never
sees raw ORM objects, only this text.

Kept intentionally provider-agnostic: this module has zero knowledge of
Gemini, OpenAI, Claude, etc. Swapping the provider later never touches
this file.
"""
from app.models.user import User
from app.repositories.sparring_repository import SparringRepository
from app.repositories.sport_repository import UserSportProfileRepository
from app.repositories.training_repository import TrainingRepository

_SESSION_TYPE_LABELS = {
    "solo": "تدريب فردي",
    "class": "صف جماعي",
    "sparring": "مبارزة تدريبية (سبارينج)",
    "conditioning": "تكييف بدني",
    "technique": "تقنية",
    "other": "أخرى",
}


async def build_user_context(user: User, db) -> str:
    """Builds the system-prompt text for one user. `db` is the active
    AsyncSession for the current request."""
    lines: list[str] = [
        "أنت 'AI Coach' داخل تطبيق Athletes Hub، مدرب رياضات قتالية ذكي ومساعد.",
        "أجب بإيجاز ووضوح، بنبرة مشجعة وعملية، واستند إلى البيانات الفعلية التالية عن الرياضي عند إعطاء نصائح:",
        "",
        f"الاسم: {user.full_name} (@{user.username})",
    ]

    # ── Sport profile(s) ──────────────────────────────────────
    profile_repo = UserSportProfileRepository(db)
    profiles = await profile_repo.get_for_user(user.id)
    if profiles:
        lines.append("\nالملفات الرياضية:")
        for p in profiles:
            sport_name = p.sport.name if p.sport else "غير محدد"
            attrs = p.attributes or {}
            attr_bits = ", ".join(f"{k}: {v}" for k, v in attrs.items() if v)
            primary_tag = " (أساسية)" if p.is_primary else ""
            lines.append(f"- {sport_name}{primary_tag}" + (f" — {attr_bits}" if attr_bits else ""))
    else:
        lines.append("\nلم يضف الرياضي أي ملف رياضي بعد.")

    # ── Recent training ──────────────────────────────────────
    training_repo = TrainingRepository(db)
    recent_sessions = await training_repo.get_recent_for_context(user.id, limit=5)
    if recent_sessions:
        lines.append("\nآخر جلسات التدريب (الأحدث أولاً):")
        for s in recent_sessions:
            type_label = _SESSION_TYPE_LABELS.get(s.session_type, s.session_type)
            date_str = s.session_date.strftime("%Y-%m-%d") if s.session_date else "?"
            intensity_str = f", شدة {s.intensity}/5" if s.intensity else ""
            lines.append(f"- {date_str}: {type_label}، {s.duration_minutes} دقيقة{intensity_str}")
    else:
        lines.append("\nلا توجد جلسات تدريب مسجلة بعد.")

    # ── Sparring activity ─────────────────────────────────────
    sparring_repo = SparringRepository(db)
    incoming = await sparring_repo.get_incoming(user.id)
    outgoing = await sparring_repo.get_outgoing(user.id)
    all_requests = incoming + outgoing
    completed = sum(1 for r in all_requests if r.status == "completed")
    accepted = sum(1 for r in all_requests if r.status == "accepted")
    pending = sum(1 for r in all_requests if r.status == "pending")
    if all_requests:
        lines.append(
            f"\nنشاط السبارينج: {completed} مكتملة، {accepted} مؤكدة قادمة، {pending} قيد الانتظار."
        )

    lines.append(
        "\nإذا كانت البيانات أعلاه غير كافية للإجابة بدقة، وضّح ذلك للرياضي واقترح عليه "
        "تسجيل جلسة تدريب أو إكمال ملفه الرياضي."
    )

    return "\n".join(lines)
