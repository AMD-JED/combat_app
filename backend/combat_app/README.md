# ⚔️ Combat Sports Network — Backend API

A professional social network backend for combat sports athletes, built with FastAPI, PostgreSQL, and clean architecture principles.

## 🏗️ Architecture

```
Repository Pattern:
  Route → Schema (Pydantic) → Repository → Model (SQLAlchemy) → PostgreSQL
```

## 📁 Project Structure

```
combat_app/
├── app/
│   ├── api/v1/endpoints/   ← Route handlers (thin layer)
│   │   ├── auth.py         ← Register, Login, Refresh, /me
│   │   ├── users.py        ← Profile, Search, Follow/Unfollow
│   │   ├── posts.py        ← Feed, Create, Like, Comment
│   │   └── exercises.py    ← Exercise library CRUD
│   │
│   ├── core/
│   │   ├── config.py       ← Settings (env vars)
│   │   ├── database.py     ← Async SQLAlchemy engine + session
│   │   ├── security.py     ← JWT + bcrypt
│   │   └── dependencies.py ← FastAPI Depends (get_current_user)
│   │
│   ├── models/             ← SQLAlchemy ORM models
│   │   ├── user.py         ← User, follows table
│   │   ├── post.py         ← Post, Comment, post_likes
│   │   └── exercise.py     ← Exercise library
│   │
│   ├── repositories/       ← Data access layer (Repository Pattern)
│   │   ├── base_repository.py   ← Generic CRUD base
│   │   ├── user_repository.py   ← User-specific queries
│   │   └── post_repository.py   ← Post/Exercise queries
│   │
│   └── schemas/            ← Pydantic models (validation + serialization)
│       ├── user.py
│       ├── post.py
│       └── exercise.py
│
├── alembic/                ← DB migrations
├── tests/                  ← Pytest async tests
├── .env.example
├── requirements.txt
└── main.py
```

## 🚀 Quick Start

### 1. Clone & Setup Environment
```bash
git clone <repo>
cd combat_app
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Configure Environment
```bash
cp .env.example .env
# Edit .env with your PostgreSQL credentials and secret key
```

### 3. Setup PostgreSQL
```bash
psql -U postgres
CREATE DATABASE combat_sports_db;
```

### 4. Run the Server
```bash
uvicorn app.main:app --reload
```

### 5. View API Docs
Open: http://localhost:8000/docs

## 🔑 API Overview

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | /api/v1/auth/register | Create account | ❌ |
| POST | /api/v1/auth/login | Login → JWT tokens | ❌ |
| POST | /api/v1/auth/refresh | Refresh access token | ❌ |
| GET | /api/v1/auth/me | Current user profile | ✅ |
| GET | /api/v1/users/search?q= | Search athletes | ❌ |
| GET | /api/v1/users/{username} | Public profile | ❌ |
| PATCH | /api/v1/users/me | Update profile | ✅ |
| POST | /api/v1/users/{id}/follow | Follow/Unfollow | ✅ |
| GET | /api/v1/posts/feed | Personalized feed | ✅ |
| POST | /api/v1/posts/ | Create post | ✅ |
| POST | /api/v1/posts/{id}/like | Like/Unlike | ✅ |
| POST | /api/v1/posts/{id}/comments | Add comment | ✅ |
| GET | /api/v1/exercises/ | Browse exercises | ❌ |
| POST | /api/v1/exercises/ | Add exercise (coaches) | ✅ |

## 🧪 Run Tests
```bash
pytest tests/ -v
```

## 🔒 Security Features
- **bcrypt** password hashing
- **JWT** Access + Refresh token rotation
- **OAuth2PasswordBearer** scheme
- CORS protection
- Input validation via Pydantic

## 📦 Tech Stack
- **FastAPI** — Modern async Python web framework
- **SQLAlchemy 2.0** — Async ORM
- **PostgreSQL + asyncpg** — Database
- **Alembic** — Database migrations
- **Pydantic v2** — Data validation
- **python-jose** — JWT handling
- **passlib[bcrypt]** — Password hashing

## 📸 Media Uploads (Cloudinary)

### Setup
1. Create a free account at [cloudinary.com](https://cloudinary.com)
2. Copy your **Cloud Name**, **API Key**, **API Secret** from the dashboard
3. Add them to your `.env` file

### Upload Flow
```
Client                    Backend                   Cloudinary
  │                          │                           │
  │── POST /uploads/avatar ──▶                           │
  │   (multipart/form-data)  │── upload_avatar() ───────▶│
  │                          │◀── { secure_url } ────────│
  │◀── { avatar_url } ───────│                           │
```

### Upload Endpoints

| Method | Endpoint | Description | Auth |
|--------|----------|-------------|------|
| POST | /api/v1/uploads/avatar | Profile picture (face-crop, WebP) | ✅ |
| POST | /api/v1/uploads/post/image | Post image (optimized + thumbnail) | ✅ |
| POST | /api/v1/uploads/post/video | Training video (H.264 MP4) | ✅ |
| POST | /api/v1/uploads/exercise/video | Exercise tutorial (coaches only) | ✅ |
| DELETE | /api/v1/uploads/{public_id} | Delete media | ✅ |

### Auto Transformations

| Type | What Cloudinary does |
|------|----------------------|
| Avatar | 400×400 face-crop → WebP |
| Post Image | Max 1080×1080, auto quality → WebP + thumbnail |
| Post Video | Transcode → H.264 MP4 + thumbnail at 1s |
| Exercise Video | 1280×720 MP4 + thumbnail at 2s |
- **Cloudinary** — Media storage & transformation
