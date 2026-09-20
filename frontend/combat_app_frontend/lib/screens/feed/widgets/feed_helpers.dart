import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';

/// "just now" / "5 min ago" / "3 h ago" / "2 d ago", then a plain date after
/// a month. Localized through ARB (ar/fr/en).
String formatRelativeTime(AppLocalizations l10n, DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return l10n.timeNow;
  if (diff.inMinutes < 60) return l10n.timeMinutes(diff.inMinutes);
  if (diff.inHours < 24) return l10n.timeHours(diff.inHours);
  if (diff.inDays < 30) return l10n.timeDays(diff.inDays);

  final local = dateTime.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

/// The prototype's purple -> indigo call-to-action gradient, derived from the
/// current sport accent so it follows football (green) / running (cyan) too.
LinearGradient accentGradient(Color accent) {
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [accent, Color.lerp(accent, const Color(0xFF4F46E5), 0.55)!],
  );
}

/// Rounded-square avatar used across the feed (the prototype's
/// `rounded-2xl` avatars — not circles).
class RoundedAvatar extends StatelessWidget {
  final String? url;
  final double size;
  final Color accent;

  const RoundedAvatar({
    super.key,
    required this.url,
    required this.accent,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).dividerColor;
    final radius = BorderRadius.circular(size * 0.36);
    final fallback = Center(
      child: Icon(Icons.person, size: size * 0.55, color: accent),
    );
    final hasUrl = url != null && url!.isNotEmpty;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.15),
        borderRadius: radius,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: borderColor),
      ),
      child: hasUrl
          ? Image.network(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            )
          : fallback,
    );
  }
}

/// Small uppercase pill with the athlete's sport (COMBAT / FOOTBALL / RUNNING).
class SportChip extends StatelessWidget {
  final SportAccent sport;

  const SportChip({super.key, required this.sport});

  @override
  Widget build(BuildContext context) {
    final color = sport.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        sport.key.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// A "send" icon that mirrors itself in right-to-left locales (Arabic), so the
/// paper plane always points in the reading direction.
class DirectionalSendIcon extends StatelessWidget {
  final double size;
  final Color color;

  const DirectionalSendIcon({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Transform.flip(
      flipX: isRtl,
      child: Icon(Icons.send_rounded, size: size, color: color),
    );
  }
}
