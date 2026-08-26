import 'package:flutter/foundation.dart' show kIsWeb;

/// Central place for API configuration.
///
/// IMPORTANT — Base URL depends on where you run the app:
///   • Android Emulator  → http://10.0.2.2:8000/api/v1
///   • iOS Simulator     → http://localhost:8000/api/v1
///   • Real device       → http://<YOUR_PC_LAN_IP>:8000/api/v1  (e.g. http://192.168.1.5:8000/api/v1)
///   • Web (chrome)      → http://localhost:8000/api/v1
///
/// [_defaultBaseUrl] auto-picks a sane default: `10.0.2.2` only makes sense
/// inside the Android emulator's virtual network — a real browser (web-server,
/// Chrome, Edge...) has no idea what that address is and every request will
/// fail with "تعذّر الاتصال بالخادم" before it even leaves the machine. `kIsWeb`
/// is a compile-time constant, so this stays a `const` default like before.
/// You can still always override with `--dart-define=API_BASE_URL=...`.
class ApiConfig {
  static const String _defaultBaseUrl =
      kIsWeb ? 'http://localhost:8000/api/v1' : 'http://10.0.2.2:8000/api/v1';

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultBaseUrl,
  );

  // Auth
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String me = '/auth/me';

  // Users
  static const String usersSearch = '/users/search';
  static String userProfile(String username) => '/users/$username';
  static const String updateMe = '/users/me';
  static String toggleFollow(int userId) => '/users/$userId/follow';

  // Uploads
  static const String uploadAvatar = '/uploads/avatar';
  static const String uploadPostImage = '/uploads/post/image';
  static const String uploadPostVideo = '/uploads/post/video';

  // Posts
  static const String postsFeed = '/posts/feed';
  static const String createPost = '/posts/';
  static String deletePost(int id) => '/posts/$id';
  static String toggleLike(int id) => '/posts/$id/like';
  static String addComment(int id) => '/posts/$id/comments';

  // Messages (Direct Messaging)
  static const String conversations = '/messages/conversations';
  static String openConversation(int userId) =>
      '/messages/conversations/$userId';
  static String conversationMessages(int conversationId) =>
      '/messages/conversations/$conversationId/messages';
  static String markConversationRead(int conversationId) =>
      '/messages/conversations/$conversationId/read';
  static String deleteMessage(int messageId) => '/messages/$messageId';
  static const String messagesWs = '/messages/ws';

  // Sports (multi-sport — see app/api/v1/endpoints/sports.py)
  static const String sportsList = '/sports/';
  static const String mySportProfiles = '/sports/me/profiles';
  static String sportProfile(int profileId) => '/sports/me/profiles/$profileId';

  // Secure storage keys
  static const String accessTokenKey = 'combat_access_token';
  static const String refreshTokenKey = 'combat_refresh_token';
}
