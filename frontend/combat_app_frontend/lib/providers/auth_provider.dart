import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/secure_storage.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final bool isLoading;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.isLoading = false,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Drives login/register/logout and holds the current user profile.
/// [GoRouter]'s redirect logic (see router.dart) listens to [AuthState.status]
/// to decide whether to show the login screen or the app itself.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _bootstrap();
  }

  final AuthService _authService = AuthService();

  /// Runs once at app startup: if a token is already stored, try to fetch
  /// the current user; otherwise go straight to "unauthenticated".
  Future<void> _bootstrap() async {
    final hasTokens = await SecureStorage.instance.hasTokens();
    if (!hasTokens) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await _authService.getMe();
      state = state.copyWith(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      // Token invalid/expired and refresh failed inside the Dio interceptor.
      await SecureStorage.instance.clear();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _authService.login(email: email, password: password);
      final user = await _authService.getMe();
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: user,
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Registers, then immediately logs in (backend returns no tokens on
  /// registration — see AuthService.register docs).
  Future<bool> register({
    required String email,
    required String username,
    required String fullName,
    required String password,
    required String passwordConfirm,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _authService.register(
        email: email,
        username: username,
        fullName: fullName,
        password: password,
        passwordConfirm: passwordConfirm,
      );
      return await login(email: email, password: password);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<void> refreshUser() async {
    try {
      final user = await _authService.getMe();
      state = state.copyWith(user: user);
    } catch (_) {
      // ignore silently — caller can retry
    }
  }

  void updateUserLocally(UserModel user) {
    state = state.copyWith(user: user);
  }

  Future<void> logout() async {
    await _authService.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
