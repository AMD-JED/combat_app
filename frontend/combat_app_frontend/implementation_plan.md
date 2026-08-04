# ⚔️ v2 Implementation Plan: Feed, Post Creation, Likes & Comments

This document details the architecture and implementation plan for adding **v2 features** to the `combat_app_frontend` Flutter app. This version adds the social feed, post creation (text/image/video/workout), post deletion, liking, commenting, and app navigation.

---

## 🛠️ Proposed Changes

### 1. Data Models & Schemas

#### [NEW] [post_model.dart](file:///C:/Users/User/Desktop/APP/combat_app/frontend/combat_app_frontend/lib/models/post_model.dart)
- Define `PostType` enum (`TEXT`, `IMAGE`, `VIDEO`, `WORKOUT`).
- Define `PostModel` matching `PostResponse` schema from FastAPI:
  - `id`, `content`, `mediaUrl`, `postType`, `tags`, `author` (`UserModel`), `likesCount`, `commentsCount`, `createdAt`.

#### [NEW] [comment_model.dart](file:///C:/Users/User/Desktop/APP/combat_app/frontend/combat_app_frontend/lib/models/comment_model.dart)
- Define `CommentModel` matching `CommentResponse` schema from FastAPI:
  - `id`, `content`, `author` (`UserModel`), `createdAt`.

---

### 2. API Services

#### [NEW] [post_service.dart](file:///C:/Users/User/Desktop/APP/combat_app/frontend/combat_app_frontend/lib/services/post_service.dart)
- Connects directly to backend endpoints:
  - `getFeed({int skip = 0, int limit = 20})` ➔ `GET /posts/feed`
  - `createPost(...)` ➔ `POST /posts/`
  - `deletePost(int postId)` ➔ `DELETE /posts/{postId}`
  - `toggleLike(int postId)` ➔ `POST /posts/{postId}/like`
  - `addComment(int postId, String content)` ➔ `POST /posts/{postId}/comments`
  - `uploadPostImage(XFile file)` ➔ `POST /uploads/post/image`
  - `uploadPostVideo(XFile file)` ➔ `POST /uploads/post/video`

---

### 3. State Management (Riverpod)

#### [NEW] [post_provider.dart](file:///C:/Users/User/Desktop/APP/combat_app/frontend/combat_app_frontend/lib/providers/post_provider.dart)
- `FeedState`: Holds posts list, loading state, error messages, and pagination info.
- `FeedNotifier`: StateNotifier managing feed actions:
  - `fetchFeed()`
  - `toggleLike(int postId)` with optimistic state update
  - `addComment(int postId, String commentText)`
  - `createPost(...)`
  - `deletePost(int postId)`

---

### 4. UI Screens & Widgets

#### [NEW] [feed_screen.dart](file:///C:/Users/User/Desktop/APP/combat_app/frontend/combat_app_frontend/lib/screens/feed/feed_screen.dart)
- Displays post feed with `RefreshIndicator`.
- Displays floating action button (FAB) for creating posts.
- Empty feed state placeholder with modern dark UI styling.

#### [NEW] [create_post_screen.dart](file:///C:/Users/User/Desktop/APP/combat_app/frontend/combat_app_frontend/lib/screens/feed/create_post_screen.dart)
- Screen/Dialog allowing users to type post text, select post type (`TEXT`, `IMAGE`, `VIDEO`, `WORKOUT`), attach image/video using `image_picker`, and post.

#### [NEW] [post_card.dart](file:///C:/Users/User/Desktop/APP/combat_app/frontend/combat_app_frontend/lib/screens/feed/widgets/post_card.dart)
- Card displaying post header (author avatar, username, sport/belt badges, timestamp).
- Post content & attached media (Image / Video preview).
- Interactive buttons for Likes (with red heart animation) and Comments (opens comments bottom sheet).

#### [NEW] [comments_bottom_sheet.dart](file:///C:/Users/User/Desktop/APP/combat_app/frontend/combat_app_frontend/lib/screens/feed/widgets/comments_bottom_sheet.dart)
- Modal sheet showing list of comments for a post and an input box to send a new comment.

#### [NEW] [main_navigation_screen.dart](file:///C:/Users/User/Desktop/APP/combat_app/frontend/combat_app_frontend/lib/screens/main_navigation_screen.dart)
- Modern bottom navigation bar switching between **Feed** and **Profile**.

#### [MODIFY] [router.dart](file:///C:/Users/User/Desktop/APP/combat_app/frontend/combat_app_frontend/lib/router.dart)
- Update routes to include `/feed`, `/create-post`, and wrap authenticated user flow in `MainNavigationScreen`.

---

## 🧪 Verification Plan

### Automated & Static Verification
1. Run `flutter analyze` to ensure 0 syntax errors or missing imports.
2. Verify models deserialize cleanly from FastAPI JSON outputs.

### Manual Verification
1. **Feed Display**: Navigate to feed, pull to refresh, verify posts load.
2. **Create Post**: Create a text post and image post; check that it appears at top of feed immediately.
3. **Like / Unlike**: Click heart icon, check like count updates smoothly and reflects on backend.
4. **Comment**: Open comment modal, type comment, submit, and verify comment appears.
5. **Delete**: Create a post, click delete icon, verify post is removed.
