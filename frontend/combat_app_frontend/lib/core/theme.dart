import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One accent per sport, mirrors the `Sport` rows seeded on the backend
/// (`feature/multi-sport` — see `seed_sports.py`). `key` MUST match the
/// backend `Sport.name`/slug exactly, since it's what the API sends/expects.
///
/// NOTE: hardcoded here as a stopgap so the UI has something to render
/// immediately. Once `sports_service.dart` is wired to `GET /api/v1/sports/`,
/// this should become data-driven (color/icon can be added as columns, or
/// kept as a small local lookup keyed by the slug the backend returns).
enum SportAccent {
  combat(key: 'combat', color: Color(0xFF8B5CF6), icon: Icons.sports_mma, label: 'قتالية'),
  football(key: 'football', color: Color(0xFF10B981), icon: Icons.sports_soccer, label: 'كرة قدم'),
  running(key: 'running', color: Color(0xFF06B6D4), icon: Icons.directions_run, label: 'جري');

  final String key;
  final Color color;
  final IconData icon;
  final String label;

  const SportAccent({
    required this.key,
    required this.color,
    required this.icon,
    required this.label,
  });

  static SportAccent fromKey(String? key) {
    return SportAccent.values.firstWhere(
      (e) => e.key == key,
      orElse: () => SportAccent.combat,
    );
  }
}

/// Design tokens + ThemeData factory matching the Athletes Hub mockup
/// (Material 3, Cairo font — supports Arabic/French/English — per-sport
/// accent color, light AND dark). Theme brightness is a user preference
/// (see `theme_mode_provider.dart`), not a fixed choice.
class AppTheme {
  // --- Light tokens (from the mockup's tailwind config, sport-agnostic) ---
  static const Color background = Color(0xFFFDF7FF);
  static const Color surface = Color(0xFFF2ECF4);
  static const Color surfaceHigh = Color(0xFFECE6EE);
  static const Color surfaceLowest = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1D1B20);
  static const Color onSurfaceVariant = Color(0xFF494551);
  static const Color outline = Color(0xFF7A7582);
  static const Color outlineVariant = Color(0xFFCBC4D2);
  static const Color error = Color(0xFFBA1A1A);

  // --- Legacy aliases -------------------------------------------------
  // Old screens (pre-redesign) reference these directly. Kept temporarily
  // so the app keeps compiling while auth/feed/profile are redesigned
  // screen-by-screen; remove once every screen uses Theme.of(context)
  // + the sport accent instead of static AppTheme colors.
  static const Color textMuted = onSurfaceVariant;
  static const Color primaryRed = error;
  static const Color gold = Color(0xFFD4AF37);

  // --- Dark tokens ------------------------------------------------------
  // Matches the dominant dark surface used across the Athletes Hub design
  // reference (PostCard, ProfileScreen, TopNavbar, BottomNavBar, AuthModal).
  // Only consumed by `themeFor(..., brightness: Brightness.dark)` and any
  // screen already migrated to `Theme.of(context)` — NOT by the legacy
  // static aliases above, so pre-redesign screens are unaffected for now.
  static const Color darkBackground = Color(0xFF08080C);
  static const Color darkSurface = Color(0xFF1A1A24);
  static const Color darkSurfaceHigh = Color(0xFF22222E);
  static const Color darkSurfaceLowest = Color(0xFF13131C);
  static const Color darkOnSurface = Color(0xFFF5F5F7);
  static const Color darkOnSurfaceVariant = Color(0xFF9A98A6);
  static const Color darkOutline = Color(0xFF8A8894);
  static const Color darkOutlineVariant = Color(0xFF35353F);
  static const Color darkError = Color(0xFFFFB4AB);

  static TextTheme _textTheme({
    required Color onSurfaceColor,
    required Color onSurfaceVariantColor,
  }) {
    // Cairo supports Arabic + Latin scripts in one family (used elsewhere
    // in the project's Arabic materials), so headings/body/labels stay
    // visually consistent across ar/fr/en instead of falling back to a
    // different system font whenever Arabic text appears.
    final headline = GoogleFonts.cairo(fontWeight: FontWeight.w800);
    final body = GoogleFonts.cairo();
    final labelCaps = GoogleFonts.cairo(fontWeight: FontWeight.w600);

    return TextTheme(
      displayLarge: headline.copyWith(
          fontSize: 48, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -0.5, color: onSurfaceColor),
      headlineMedium: headline.copyWith(
          fontSize: 24, fontWeight: FontWeight.w700, height: 1.3, color: onSurfaceColor),
      titleMedium: headline.copyWith(
          fontSize: 18, fontWeight: FontWeight.w700, color: onSurfaceColor),
      bodyLarge: body.copyWith(fontSize: 18, height: 1.6, color: onSurfaceColor),
      bodyMedium: body.copyWith(fontSize: 16, height: 1.5, color: onSurfaceColor),
      bodySmall: body.copyWith(fontSize: 14, height: 1.4, color: onSurfaceVariantColor),
      labelSmall: labelCaps.copyWith(
          fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: onSurfaceVariantColor),
    );
  }

  /// Builds the full app [ThemeData] tinted with [accent]'s color, in either
  /// [Brightness.light] or [Brightness.dark]. Call with the athlete's chosen
  /// sport (default [SportAccent.combat] pre-login / during onboarding
  /// before a sport is picked) and the user's theme preference.
  static ThemeData themeFor(SportAccent accent, {Brightness brightness = Brightness.light}) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? darkBackground : background;
    final surf = isDark ? darkSurface : surface;
    final surfLowest = isDark ? darkSurfaceLowest : surfaceLowest;
    final onSurf = isDark ? darkOnSurface : onSurface;
    final onSurfVariant = isDark ? darkOnSurfaceVariant : onSurfaceVariant;
    final outlineVariantC = isDark ? darkOutlineVariant : outlineVariant;
    final errorC = isDark ? darkError : error;

    final base = ThemeData(useMaterial3: true, brightness: brightness);
    final textTheme = _textTheme(onSurfaceColor: onSurf, onSurfaceVariantColor: onSurfVariant);

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent.color,
        brightness: brightness,
      ).copyWith(
        primary: accent.color,
        onPrimary: Colors.white,
        surface: surf,
        onSurface: onSurf,
        error: errorC,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onSurf,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surf,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: textTheme.bodyMedium?.copyWith(color: onSurfVariant),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent.color,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
          textStyle: textTheme.labelSmall?.copyWith(fontSize: 14, color: Colors.white),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent.color),
      ),
      cardTheme: CardThemeData(
        color: surfLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: outlineVariantC.withValues(alpha: 0.4)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfLowest,
        indicatorColor: accent.color.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.all(textTheme.labelSmall?.copyWith(letterSpacing: 0.2)),
      ),
    );
  }

  /// Convenience getter used by the Settings preview and any call site that
  /// just wants "the dark theme, combat-tinted" without going through
  /// [themeFor] directly.
  static ThemeData get dark => themeFor(SportAccent.combat, brightness: Brightness.dark);
}
