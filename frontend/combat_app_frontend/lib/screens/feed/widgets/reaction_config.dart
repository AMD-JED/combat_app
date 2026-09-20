import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/post_model.dart';

/// Visual identity of one reaction — mirrors `getReactionsList` in the React
/// prototype's `AthleticReactionsBar.tsx` (same emojis, same colors, same
/// order). Labels come from ARB so they follow the app language.
class ReactionConfig {
  final ReactionType type;
  final String label;
  final String emoji;
  final Color color;

  const ReactionConfig({
    required this.type,
    required this.label,
    required this.emoji,
    required this.color,
  });

  /// Text/icon color of this reaction on the current theme: the prototype's
  /// `*-400` shades read well on dark surfaces; on light surfaces they are
  /// darkened a bit so the label stays legible.
  Color foreground(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? color : Color.lerp(color, Colors.black, 0.35)!;
  }
}

/// All six reactions, in display order. The last one ("sport") changes with
/// the athlete's sport: Guerrier / Buteur / Sprinter in the prototype.
///
/// The backend doesn't store a sport per post, so [sport] is the viewer's
/// current sport accent (see `currentSportAccentProvider`).
List<ReactionConfig> reactionConfigsFor(AppLocalizations l10n, SportAccent sport) {
  return [
    ReactionConfig(
      type: ReactionType.respect,
      label: l10n.reactionRespect,
      emoji: '👍',
      color: const Color(0xFF60A5FA),
    ),
    ReactionConfig(
      type: ReactionType.fire,
      label: l10n.reactionFire,
      emoji: '🔥',
      color: const Color(0xFFFBBF24),
    ),
    ReactionConfig(
      type: ReactionType.strength,
      label: l10n.reactionStrength,
      emoji: '💪',
      color: const Color(0xFFFB7185),
    ),
    ReactionConfig(
      type: ReactionType.precision,
      label: l10n.reactionPrecision,
      emoji: '🎯',
      color: const Color(0xFF22D3EE),
    ),
    ReactionConfig(
      type: ReactionType.champion,
      label: l10n.reactionChampion,
      emoji: '👑',
      color: const Color(0xFFFACC15),
    ),
    _sportReaction(l10n, sport),
  ];
}

ReactionConfig reactionConfigFor(
  ReactionType type,
  AppLocalizations l10n,
  SportAccent sport,
) {
  return reactionConfigsFor(l10n, sport).firstWhere((r) => r.type == type);
}

ReactionConfig _sportReaction(AppLocalizations l10n, SportAccent sport) {
  switch (sport) {
    case SportAccent.combat:
      return ReactionConfig(
        type: ReactionType.sport,
        label: l10n.reactionSportCombat,
        emoji: '🥊',
        color: sport.color,
      );
    case SportAccent.football:
      return ReactionConfig(
        type: ReactionType.sport,
        label: l10n.reactionSportFootball,
        emoji: '⚽',
        color: sport.color,
      );
    case SportAccent.running:
      return ReactionConfig(
        type: ReactionType.sport,
        label: l10n.reactionSportRunning,
        emoji: '🏃',
        color: sport.color,
      );
  }
}
