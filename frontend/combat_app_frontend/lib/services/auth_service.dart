import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/constants.dart';
import '../core/secure_storage.dart';
import '../models/user_model.dart';

/// Talks to `app/api/v1/endpoints/auth.py`.
class AuthService {
  final Dio _dio = ApiClient.instance.dio;

  /// POST /auth/register
  /// NOTE: the backend's `UserCreate` schema requires `password_confirm`
  /// and does NOT return tokens — only the created user. Call [login]
  /// right after a successful registration.
  Future<UserModel> register({
    required String email,
    required String username,
    required String fullName,
    required String password,
    required String passwordConfirm,
  }) async {
    try {
      final response = await _dio.post(ApiConfig.register, data: {
        'email': email,
        'username': username,
        'full_name': fullName,
        'password': password,
        'password_confirm': passwordConfirm,
      });
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /auth/login
  /// IMPORTANT: this endpoint uses FastAPI's `OAuth2PasswordRequestForm`,
  /// so the body MUST be `application/x-www-form-urlencoded`, not JSON.
  /// The form's `username` field is the user's EMAIL (see backend comment
  /// `# username field = email`).
  Future<void> login({required String email, required String password}) async {
    try {
      final response = await _dio.post(
        ApiConfig.login,
        data: FormData.fromMap({'username': email, 'password': password}),
        options: Options(contentType: Headers.multipartFormDataContentType),
      );
      final accessToken = response.data['access_token'] as String;
      final refreshToken = response.data['refresh_token'] as String;
      await SecureStorage.instance.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET /auth/me — requires a valid access token (attached automatically).
  Future<UserModel> getMe() async {
    try {
      final response = await _dio.get(ApiConfig.me);
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  Future<void> logout() async {
    await SecureStorage.instance.clear();
  }
}
