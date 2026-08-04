/// Central place for API configuration.
///
/// IMPORTANT — Base URL depends on where you run the app:
///   • Android Emulator  → http://10.0.2.2:8000/api/v1
///   • iOS Simulator     → http://localhost:8000/api/v1
///   • Real device       → http://<YOUR_PC_LAN_IP>:8000/api/v1  (e.g. http://192.168.1.5:8000/api/v1)
///   • Web (chrome)      → http://localhost:8000/api/v1
///
/// Change [ApiConfig.baseUrl] below depending on your target, or better —
/// pass it with `--dart-define=API_BASE_URL=...` at build/run time.
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
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

  // Secure storage keys
  static const String accessTokenKey = 'combat_access_token';
  static const String refreshTokenKey = 'combat_refresh_token';
}
