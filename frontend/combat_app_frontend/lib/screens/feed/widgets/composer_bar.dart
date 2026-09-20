import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/sports_provider.dart';
import 'feed_helpers.dart';

/// The "share a workout, a sparring..." bar at the top of the feed — port of
/// the prototype's `CreatePostInput.tsx`. It replaces the old floating "+"
/// button: tapping the bar (or the photo icon) opens the create-post screen.
///
/// The prototype's quick-category buttons (sparring challenge, workout log,
/// highlight) lead to features that don't exist in the app yet, so they are
/// not rendered.
class ComposerBar extends ConsumerWidget {
  const ComposerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).user;
    final sport = ref.watch(currentSportAccentProvider);
    final accent = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    final divider = theme.dividerColor;

    void openComposer() => context.push('/create-post');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: Row(
        children: [
          RoundedAvatar(url: user?.avatarUrl, accent: accent),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: openComposer,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: divider),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.composerHint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SportChip(sport: sport),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: l10n.composerMediaTooltip,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: openComposer,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: divider),
                ),
                child: Icon(Icons.image_outlined, size: 20, color: muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
