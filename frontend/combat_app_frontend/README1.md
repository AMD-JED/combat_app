# ⚔️ Combat Sports Network — Frontend Deliverables (v1 + v3)

هذا الأرشيف يجمع كل الملفات اللي تم إنشاؤها في هذه المحادثة، بالترتيب.

---

## 📁 `v1_auth_profile/` — مشروع Flutter كامل وجاهز للتشغيل

**الحالة: مكتمل ومستقل بذاته (مشروع Flutter كامل، مو مجرد ملفات إضافية).**

يغطي: تسجيل حساب / تسجيل دخول / بقاء الجلسة (JWT + تجديد تلقائي) / عرض وتعديل
الملف الشخصي / رفع صورة شخصية.

بُني بالرجوع المباشر للكود الفعلي (`codebase_documentation.pdf`) للتأكد من:
- تسجيل الدخول عبر `OAuth2PasswordRequestForm` (form-data، حقل `username` = البريد الإلكتروني)
- `/auth/register` لا يرجع توكنات (يُتبع بـ `login` تلقائيًا)
- حقول `SportType` / `WeightClass` مطابقة حرفيًا لقيم enum بالباك اند

يحتوي `README.md` خاص بداخله فيه شرح كامل لخطوات التشغيل (`flutter create .`، `flutter pub get`،
الصلاحيات، الـ Base URL...).

**هيكل مختصر:**
```
lib/
├── main.dart, router.dart
├── core/          (api_client, secure_storage, constants, theme, api_exception)
├── models/        (user_model.dart)
├── services/      (auth_service, user_service, upload_service)
├── providers/     (auth_provider)
└── screens/       (splash, auth/login+register, profile/view+edit)
```

---

## 📁 `v3_messaging_additions/` — ملفات إضافية (تُدمج فوق مشروعك الحالي بعد v2)

**الحالة: ملفات جاهزة، تحتاج دمج يدوي حسب "خطوة بخطوة" بالأسفل — مو مشروع مستقل.**

يغطي: قائمة المحادثات، شات مباشر عبر WebSocket، مؤشر الكتابة، إشعارات القراءة،
حذف الرسائل (soft-delete)، وشاشة عرض بروفايل مستخدم آخر مع زر "مراسلة".

بُني بالرجوع المباشر لـ `messages.py` / `connection_manager.py` الفعليين للتأكد من:
- الاتصال بـ `/messages/ws?token=<JWT>` (query param، مو header)
- إغلاق الاتصال بكود `4001` عند انتهاء صلاحية التوكن
- رسالة `new_message` تصل للطرفين معًا (تجنّب التكرار عبر ID)
- سجل الرسائل يرجع الأحدث أولًا (يُعكس بالكود قبل العرض)

**الملفات:**
```
lib/models/message_model.dart                      ← MessageModel + ConversationModel
lib/services/message_service.dart                  ← REST: conversations/messages/read/delete
lib/core/chat_socket_service.dart                   ← WebSocket wrapper
lib/providers/conversations_provider.dart           ← حالة قائمة المحادثات
lib/providers/chat_provider.dart                     ← حالة محادثة واحدة + ربط WebSocket
lib/screens/messages/conversations_screen.dart      ← شاشة قائمة المحادثات
lib/screens/messages/chat_screen.dart                ← شاشة الشات المباشر
lib/screens/messages/widgets/message_bubble.dart    ← فقاعة رسالة واحدة
lib/screens/profile/public_profile_screen.dart      ← بروفايل مستخدم آخر + زر "مراسلة"
```

### خطوات الدمج (ملخّص — التفاصيل الكاملة كانت بالمحادثة):
1. أضف `web_socket_channel: ^2.4.0` في `pubspec.yaml` ثم `flutter pub get`
2. انسخ الملفات أعلاه لنفس المسارات داخل `lib/` بمشروعك
3. أضف endpoints الرسائل الجديدة داخل `ApiConfig` بملف `core/constants.dart`
4. أضف مسارات `/messages`, `/messages/:conversationId`, `/u/:username` في `router.dart`
5. أضف تبويب "الرسائل" (مع badge للعدد غير المقروء) في شاشة التنقل السفلي
6. اربط النقر على اسم/صورة أي مستخدم (بالفيد، بالبحث...) بـ `context.push('/u/$username')`
7. اختبار حقيقي يحتاج جهازين/حسابين بنفس الوقت للتأكد من وصول الرسائل الفوري

---

## 📄 `v3_messaging_implementation_plan.md` — خطة التنفيذ الكاملة (توثيق فقط)

وثيقة تخطيط بنفس أسلوب `implementation_plan.md` اللي أرسلته لي لـ v2، توثّق:
- العقد الكامل لموديول Direct Messaging (REST + WebSocket) كما هو بالكود الفعلي
- كل الملفات المطلوب إنشاؤها/تعديلها مع سبب كل واحد
- خطة تحقق يدوية وآلية (اختبار جهازين، انقطاع الشبكة، انتهاء التوكن...)
- ملاحظة ختامية عن آخر جزء متبقي بالباك اند: **مكتبة التمارين (Exercise Library)** كـ v4 مقترح

---

## 🗺️ الحالة الإجمالية للمشروع

| الوحدة (Backend) | Frontend | الملف/المجلد |
|---|---|---|
| Authentication | ✅ مكتمل | `v1_auth_profile/` |
| Profile (view/edit + avatar) | ✅ مكتمل | `v1_auth_profile/` |
| Community & Feed | ✅ مكتمل (بنيته أنت بنفسك بناءً على `implementation_plan.md`) | — |
| Direct Messaging | 🟡 ملفات جاهزة، تحتاج دمج يدوي | `v3_messaging_additions/` |
| Exercise Library | ⏸️ لم يُبدأ بعد | مقترح كـ v4 |

**الخطوة التالية المنطقية:** دمج ملفات v3 حسب الخطوات أعلاه، ثم البدء بـ v4 (مكتبة التمارين)
إذا رغبت.
