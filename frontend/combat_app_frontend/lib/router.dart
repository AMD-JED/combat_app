import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/auth_provider.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/feed/create_post_screen.dart';
import 'screens/profile/edit_profile_screen.dart';
import 'screens/profile/public_profile_screen.dart';
import 'screens/messages/chat_screen.dart';
import 'models/user_model.dart';

class _AuthRouterRefresh extends ChangeNotifier {
  _AuthRouterRefresh(Ref ref) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.status != next.status) {
        notifyListeners();
      }
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRouterRefresh(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isSplash = state.matchedLocation == '/';
      final isAuthRoute = state.matchedLocation.startsWith('/login') ||
          state.matchedLocation.startsWith('/register');

      if (authState.status == AuthStatus.unknown) {
        return isSplash ? null : '/';
      }

      final loggedIn = authState.status == AuthStatus.authenticated;

      if (!loggedIn && !isAuthRoute) return '/login';
      if (loggedIn && (isAuthRoute || isSplash)) return '/main';

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/main', builder: (context, state) => const MainNavigationScreen()),
      GoRoute(path: '/create-post', builder: (context, state) => const CreatePostScreen()),
      GoRoute(
        path: '/profile/edit',
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/u/:username',
        builder: (context, state) => PublicProfileScreen(
          username: state.pathParameters['username']!,
        ),
      ),
      GoRoute(
        path: '/messages/:conversationId',
        builder: (context, state) {
          final conversationId = int.parse(state.pathParameters['conversationId']!);
          final otherUser = state.extra as UserModel;
          return ChatScreen(conversationId: conversationId, otherUser: otherUser);
        },
      ),
    ],
  );
});
