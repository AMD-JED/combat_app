# ⚔️ Combat Sports Network — Flutter Frontend (v1: Auth + Profile)

هذا أول إصدار من الـ Frontend، ويغطي فقط: **تسجيل / دخول / عرض وتعديل الملف الشخصي (بما فيه رفع الصورة الشخصية)**.
مبني ليتصل مباشرة مع `combat_app_backend_v3` (نفس الـ endpoints والحقول بالضبط، تم التحقق منها من الكود الفعلي).

## 📁 هيكل المشروع

```
lib/
├── main.dart                      ← نقطة الدخول (Riverpod + GoRouter + Theme)
├── router.dart                    ← التنقل + منطق التوجيه حسب حالة تسجيل الدخول
├── core/
│   ├── constants.dart             ← Base URL + مسارات كل الـ endpoints
│   ├── api_client.dart            ← Dio + إرفاق JWT تلقائيًا + تجديد التوكن عند 401
│   ├── secure_storage.dart        ← تخزين آمن للتوكنات (flutter_secure_storage)
│   ├── api_exception.dart         ← تحويل أخطاء الـ Backend لرسائل مفهومة
│   └── theme.dart                 ← الثيم الداكن (أحمر/ذهبي)
├── models/
│   └── user_model.dart            ← مطابق تمامًا لـ UserPublicResponse/UserPrivateResponse
├── services/
│   ├── auth_service.dart          ← register / login / refresh / me
│   ├── user_service.dart          ← عرض/تعديل/بحث المستخدمين
│   └── upload_service.dart        ← رفع الصورة الشخصية (Cloudinary عبر الـ Backend)
├── providers/
│   └── auth_provider.dart         ← StateNotifier يدير حالة تسجيل الدخول بالكامل
└── screens/
    ├── splash/splash_screen.dart
    ├── auth/login_screen.dart
    ├── auth/register_screen.dart
    └── profile/{profile_screen.dart, edit_profile_screen.dart}
```

## ⚠️ نقاط مهمة تمت مطابقتها بدقة مع الـ Backend الفعلي

1. **`POST /auth/login` يستخدم `OAuth2PasswordRequestForm`** — الطلب مُرسل كـ
   `multipart/form-data` وليس JSON، وحقل `username` هو **البريد الإلكتروني** (هذا سلوك
   الـ Backend نفسه، مو خطأ). راجع `auth_service.dart::login()`.
2. **`POST /auth/register` لا يرجع أي توكنات** — يرجع فقط بيانات المستخدم. لذلك بعد
   التسجيل مباشرة، التطبيق يستدعي `login()` تلقائيًا (`auth_provider.dart::register()`).
3. **حقول المستخدم مطابقة لـ `schemas/user.py`**: `sport_type` (9 قيم)، `weight_class`
   (9 فئات وزن)، `belt_rank`، `gym_affiliation`، `bio`، `avatar_url`، `location`،
   `wins/losses/draws`، `is_coach`. القيم النصية لـ enums (مثل `"Muay Thai"` بمسافة)
   مطابقة تمامًا لما يرسله الـ Backend.
4. **`PATCH /users/me` يرجع `UserPublicResponse`** (بدون `email`) — الكود يدمج الرد مع
   بيانات المستخدم الخاصة الموجودة محليًا حتى لا تُفقد.
5. **رفع الصورة (`POST /uploads/avatar`) يحفظ الرابط على السيرفر تلقائيًا** — لا حاجة
   لاستدعاء `PATCH /users/me` بعدها لحفظ `avatar_url`.

## 🚀 التشغيل خطوة بخطوة

### 1. أنشئ مجلدات المنصّات (Android/iOS/إلخ)
هذا المشروع يحتوي فقط على `lib/` و`pubspec.yaml` (الكود المصدري). شغّل هذا الأمر
مرة واحدة داخل مجلد المشروع لتوليد مجلدات `android/` و`ios/` تلقائيًا:

```bash
flutter create . --project-name combat_app_frontend --org com.combatsports
```

⚠️ هذا الأمر ما راح يمس ملفات `lib/` أو `pubspec.yaml` الموجودة — فقط يضيف المنصّات الناقصة.

### 2. ثبّت الحزم
```bash
flutter pub get
```

### 3. أضف الصلاحيات المطلوبة لرفع الصور (image_picker)

**Android** — في `android/app/src/main/AndroidManifest.xml` (عادة موجودة تلقائيًا، لكن تأكد):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

**iOS** — في `ios/Runner/Info.plist` أضف:
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>نحتاج الوصول لمكتبة الصور لاختيار صورتك الشخصية</string>
```

### 4. حدد الـ Base URL الصحيح حسب بيئة التشغيل
افتراضيًا الكود يستخدم `http://10.0.2.2:8000/api/v1` (مناسب لمحاكي Android). لتغييره:

```bash
# محاكي iOS أو Chrome
flutter run --dart-define=API_BASE_URL=http://localhost:8000/api/v1

# جهاز حقيقي على نفس شبكة الواي فاي (استبدل بـ IP جهازك)
flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000/api/v1
```

### 5. شغّل الـ Backend أولًا
```bash
cd combat_app
uvicorn app.main:app --reload
```

### 6. شغّل التطبيق
```bash
flutter run
```

## 🧪 اختبار سريع لتدفق الاستخدام
1. افتح التطبيق → شاشة تسجيل الدخول تظهر تلقائيًا (لا يوجد توكن محفوظ)
2. اضغط "أنشئ حسابًا جديدًا" → عبّي البيانات → يسجلك دخول تلقائيًا وينقلك لصفحة البروفايل
3. اضغط أيقونة القلم لتعديل البروفايل → غيّر الرياضة/الوزن/النبذة → احفظ
4. اضغط أيقونة الكاميرا الصغيرة على الصورة لرفع صورة شخصية جديدة
5. أغلق التطبيق وأعد فتحه → لازم يدخلك مباشرة على البروفايل بدون تسجيل دخول من جديد
   (بفضل التوكنات المحفوظة في `flutter_secure_storage`)

## 📌 الخطوة القادمة (v2 المقترح)
- **Feed**: `GET /posts/feed`, `POST /posts/`, `POST /posts/{id}/like`, `POST /posts/{id}/comments`
- رفع صور/فيديوهات المنشورات عبر `/uploads/post/image` و `/uploads/post/video`

ثم **v3**:
- **Messages**: قائمة المحادثات + شاشة شات + WebSocket مباشر (`ConnectionManager` + Redis pub/sub)
