import 'package:dio/dio.dart';
import 'constants.dart';
import 'secure_storage.dart';

/// Central Dio instance used by every service.
///
/// Responsibilities:
///  1. Attach `Authorization: Bearer <access_token>` to every request.
///  2. On a 401 response, try `/auth/refresh` once using the stored
///     refresh token; if that succeeds, retry the original request.
///     If refresh also fails, clear tokens so the app can redirect to /login.
class ApiClient {
  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Accept': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Don't attach a (possibly stale) token to the auth endpoints themselves.
          final isAuthCall = options.path.contains(ApiConfig.login) ||
              options.path.contains(ApiConfig.register) ||
              options.path.contains(ApiConfig.refresh);

          if (!isAuthCall) {
            final token = await SecureStorage.instance.getAccessToken();
            if (token != null) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          final isUnauthorized = error.response?.statusCode == 401;
          final isRefreshCall = error.requestOptions.path.contains(ApiConfig.refresh);

          if (isUnauthorized && !isRefreshCall) {
            final refreshed = await _tryRefreshToken();
            if (refreshed != null) {
              // Retry the original request with the new access token.
              final retryOptions = error.requestOptions;
              retryOptions.headers['Authorization'] = 'Bearer $refreshed';
              try {
                final response = await _dio.fetch(retryOptions);
                return handler.resolve(response);
              } catch (_) {
                // fall through to clearing tokens below
              }
            }
            // Refresh failed (or retry failed) — force logout.
            await SecureStorage.instance.clear();
          }
          return handler.next(error);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._internal();
  late final Dio _dio;

  Dio get dio => _dio;

  /// Attempts to exchange the stored refresh token for a new access token.
  /// Returns the new access token on success, or null on failure.
  Future<String?> _tryRefreshToken() async {
    final refreshToken = await SecureStorage.instance.getRefreshToken();
    if (refreshToken == null) return null;

    try {
      final response = await Dio(BaseOptions(baseUrl: ApiConfig.baseUrl)).post(
        ApiConfig.refresh,
        data: {'refresh_token': refreshToken},
      );
      final newAccess = response.data['access_token'] as String;
      final newRefresh = response.data['refresh_token'] as String;
      await SecureStorage.instance.saveTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );
      return newAccess;
    } catch (_) {
      return null;
    }
  }
}
