import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'constants.dart';

/// Thin wrapper around FlutterSecureStorage for JWT access/refresh tokens.
class SecureStorage {
  SecureStorage._();
  static final SecureStorage instance = SecureStorage._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: ApiConfig.accessTokenKey, value: accessToken);
    await _storage.write(key: ApiConfig.refreshTokenKey, value: refreshToken);
  }

  Future<String?> getAccessToken() => _storage.read(key: ApiConfig.accessTokenKey);

  Future<String?> getRefreshToken() => _storage.read(key: ApiConfig.refreshTokenKey);

  Future<void> clear() async {
    await _storage.delete(key: ApiConfig.accessTokenKey);
    await _storage.delete(key: ApiConfig.refreshTokenKey);
  }

  Future<bool> hasTokens() async {
    final access = await getAccessToken();
    return access != null && access.isNotEmpty;
  }
}
