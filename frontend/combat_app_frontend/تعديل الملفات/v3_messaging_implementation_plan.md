# ⚔️ v3 Implementation Plan: Direct Messaging (Real-time)

This document details the architecture and implementation plan for adding **v3 features** to
`combat_app_frontend`: conversation list, message history, real-time WebSocket chat, typing
indicators, read receipts, and soft-delete. All contracts below were verified directly against
the backend source (`app/api/v1/endpoints/messages.py`, `app/models/message.py`,
`app/schemas/message.py`, `app/services/connection_manager.py`) — not assumed.

---

## 🔌 Verified Backend Contract

### REST Endpoints (`/api/v1/messages`)
| Method | Path | Description |
|---|---|---|
| GET | `/conversations` | List all my conversations, newest activity first → `List[ConversationResponse]` |
| POST | `/conversations/{user_id}` | Open or create a DM with another user → `{conversation_id, created}` |
| GET | `/conversations/{conversation_id}/messages?skip=&limit=` | Paginated history, **newest first** (client must reverse for display) → `List[MessageResponse]` |
| POST | `/conversations/{conversation_id}/read` | Mark all unread messages as read → `{marked_read: int}` |
| DELETE | `/{message_id}` | Soft-delete a message (sender only) → `204 No Content` |

### WebSocket — `WS /api/v1/messages/ws?token=<JWT access token>`
Auth is via **query param**, not header (WebSocket handshake limitation) — token is the same
access token used for REST calls.

**Client → Server** (`WSIncomingMessage`):
```json
{ "type": "send_message", "conversation_id": 5, "content": "yo!", "media_url": null, "media_type": null }
{ "type": "mark_read", "conversation_id": 5 }
{ "type": "typing", "conversation_id": 5 }
```

**Server → Client** (`WSOutgoingMessage`):
```json
{ "event": "connected", "data": { "user_id": 3, "message": "..." } }
{ "event": "new_message", "data": { ...MessageResponse } }
{ "event": "message_read", "data": { "conversation_id": 5, "read_by": 3 } }
{ "event": "user_typing", "data": { "user_id": 3, "username": "...", "conversation_id": 5 } }
{ "event": "error", "data": { "detail": "..." } }
```
⚠️ On invalid/expired token the server closes the socket with code `4001` — client must catch
this and redirect to a fresh REST-based reconnect (refresh access token first, then reconnect).

⚠️ `new_message` events are pushed to **both** participants (including the sender's own other
devices) — client must dedupe/ignore if the message is already shown optimistically.

### Schemas → Dart Models
- `MessageResponse`: `id`, `conversation_id`, `sender` (`UserPublicResponse`), `content?`,
  `media_url?`, `media_type?` (`"image"|"video"`), `is_read`, `deleted_at?`, `created_at`.
  If `deleted_at` is set, treat as "🚫 تم حذف هذه الرسالة" regardless of `content`.
- `ConversationResponse`: `id`, `other_user` (`UserPublicResponse`), `last_message?`
  (`MessageResponse`), `unread_count`, `last_message_at`.

---

## 🛠️ Proposed Changes

### 1. Data Models
#### [NEW] `models/message_model.dart`
- `MessageModel` matching `MessageResponse` exactly (reuses `UserModel` for `sender`).
- `ConversationModel` matching `ConversationResponse` exactly (reuses `UserModel` for `other_user`).

### 2. Services
#### [NEW] `services/message_service.dart` (REST)
- `getConversations()` → `GET /messages/conversations`
- `openConversation(int userId)` → `POST /messages/conversations/{user_id}`
- `getMessages(int conversationId, {skip, limit})` → `GET /messages/conversations/{id}/messages`
- `markRead(int conversationId)` → `POST /messages/conversations/{id}/read`
- `deleteMessage(int messageId)` → `DELETE /messages/{message_id}`

#### [NEW] `core/chat_socket_service.dart` (WebSocket)
- Wraps `web_socket_channel`, connects to `ws(s)://<host>/api/v1/messages/ws?token=<access_token>`.
- Exposes a `Stream<Map<String, dynamic>>` of parsed server events.
- Exposes `sendMessage()`, `markRead()`, `sendTyping()` helpers that encode `WSIncomingMessage` JSON.
- Handles close code `4001` by surfacing a `needsReauth` signal instead of silently dying.
- Auto-reconnect with backoff while the conversation screen is open; closes cleanly on dispose.

### 3. State Management (Riverpod)
#### [NEW] `providers/conversations_provider.dart`
- `ConversationsNotifier`: fetches/refreshes the conversation list, updates `unread_count` /
  `last_message` in place when a `new_message` or `message_read` WS event arrives for any
  conversation (so the list screen stays live even while a chat isn't open).

#### [NEW] `providers/chat_provider.dart` (per-conversation, via `family`)
- `ChatNotifier`: holds message list for one conversation, connects the WebSocket on screen
  open, appends incoming `new_message` events, applies `message_read` (marks own sent messages
  read), surfaces `user_typing` as a transient "typing…" state, and disconnects on screen close.
- `sendMessage()` optimistically appends a local pending message, then reconciles with the
  server echo (matched by conversation_id + content + sender_id, since there's no client-side
  temp ID in the current backend payload).

### 4. UI Screens & Widgets
#### [NEW] `screens/messages/conversations_screen.dart`
- List of conversations: avatar, name, last message preview, relative timestamp, unread badge.
- Pull-to-refresh; tapping opens `chat_screen.dart`.

#### [NEW] `screens/messages/chat_screen.dart`
- Reversed `ListView` of message bubbles (own vs. other, styled per the app's dark/red/gold theme).
- Typing indicator row driven by `user_typing` events (auto-clears after ~3s of silence).
- Text input + send button; calls `mark_read` automatically when the screen opens/gains focus.
- Deleted messages render the "🚫 message deleted" placeholder instead of content.

#### [NEW] `screens/messages/widgets/message_bubble.dart`
- Single bubble widget: content/media, timestamp, read-receipt check-marks for own messages.

#### [MODIFY] `screens/main_navigation_screen.dart`
- Add a third bottom-nav tab: **Messages**, with an unread-count badge sourced from
  `conversations_provider`.

#### [MODIFY] `router.dart`
- Add `/messages` (conversations list) and `/messages/:conversationId` (chat screen) routes.

#### [MODIFY] `screens/profile/profile_screen.dart` (viewing someone else's profile — future)
- Add a "Message" button that calls `openConversation()` then navigates to the chat screen.
  *(Only relevant once a "view other user's profile" screen exists — flagged for v3.1 if not
  already present.)*

### 5. New Dependency
- `web_socket_channel: ^2.4.0` (not yet in `pubspec.yaml` from v1/v2 — needs adding).

---

## 🧪 Verification Plan

### Automated & Static
1. `flutter analyze` — 0 errors.
2. Confirm `MessageModel`/`ConversationModel` deserialize cleanly against real backend JSON
   (including the `deleted_at: null` and populated cases).

### Manual
1. **Two-device test**: log in as two different users (two emulators/devices), open a
   conversation from each side, confirm messages arrive in real time on both.
2. **Typing indicator**: type in one client, confirm "typing…" appears on the other within ~1s
   and clears after stopping.
3. **Read receipts**: open the chat as the recipient, confirm the sender's bubble updates to
   "read" without a manual refresh.
4. **Reconnect handling**: force-quit Wi-Fi briefly mid-chat, confirm the socket reconnects and
   history stays consistent (no duplicate bubbles).
5. **Expired token**: manually expire the access token, confirm the socket closes with 4001 and
   the app refreshes the token / prompts re-login gracefully instead of hanging.
6. **Soft-delete**: delete a sent message, confirm it shows the deleted placeholder on both ends.

---

## 📌 After v3 — v4 (remaining, per `PROJECT_STATUS.md`)
**Exercise Library** (`GET/POST /exercises/`, coach-only video uploads via
`/uploads/exercise/video`) is the last uncovered backend module. Proposed for v4:
- `exercise_model.dart` (category, difficulty, sport_types, media, sets/reps/rest — already
  verified against `app/models/exercise.py` and `app/schemas/exercise.py`).
- `exercise_service.dart`, `exercises_provider.dart`.
- `exercise_library_screen.dart` (filterable by category/difficulty/sport), `exercise_detail_screen.dart`,
  and (for `is_coach` users only) an "Upload Tutorial" flow reusing the video-upload pattern from v2.
