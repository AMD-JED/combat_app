import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../models/sport_model.dart';
import '../services/sports_service.dart';

/// Full catalog of sports available on the platform (`GET /sports/`).
/// Public endpoint — safe to fetch before login (used by the register
/// screen's sport picker).
final sportsListProvider = FutureProvider<List<SportModel>>((ref) async {
  return SportsService().listSports();
});

class SportProfilesState {
  final List<UserSportProfileModel> profiles;
  final bool isLoading;
  final String? errorMessage;

  const SportProfilesState({
    this.profiles = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  SportProfilesState copyWith({
    List<UserSportProfileModel>? profiles,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SportProfilesState(
      profiles: profiles ?? this.profiles,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// The sport used to tint the whole app. Falls back to combat until the
  /// person has a primary profile (e.g. mid-onboarding).
  UserSportProfileModel? get primary {
    if (profiles.isEmpty) return null;
    return profiles.firstWhere((p) => p.isPrimary, orElse: () => profiles.first);
  }
}

/// Holds the logged-in user's own sport profiles (`GET/POST /sports/me/profiles`).
/// `main_navigation_screen.dart` triggers the initial fetch after login,
/// same pattern as `conversationsProvider`.
class SportProfilesNotifier extends StateNotifier<SportProfilesState> {
  SportProfilesNotifier() : super(const SportProfilesState());

  final SportsService _service = SportsService();

  Future<void> fetchMyProfiles() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final profiles = await _service.getMyProfiles();
      state = state.copyWith(profiles: profiles, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Used by the register flow's sport-picker step.
  Future<bool> addSport(String sportSlug) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final profile = await _service.addSportProfile(
        sportSlug: sportSlug,
        isPrimary: state.profiles.isEmpty, // first sport chosen becomes primary
      );
      state = state.copyWith(profiles: [...state.profiles, profile], isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  void reset() => state = const SportProfilesState();
}

final sportProfilesProvider =
    StateNotifierProvider<SportProfilesNotifier, SportProfilesState>((ref) {
  return SportProfilesNotifier();
});

/// Derives the [SportAccent] used to tint `MaterialApp.theme` from the
/// user's primary sport profile. Defaults to [SportAccent.combat] when
/// no profile exists yet (pre-login, or mid-onboarding before a sport
/// is picked) so the app never renders with an undefined color scheme.
final currentSportAccentProvider = Provider<SportAccent>((ref) {
  final primarySlug = ref.watch(sportProfilesProvider).primary?.sport.slug;
  return SportAccent.fromKey(primarySlug);
});
