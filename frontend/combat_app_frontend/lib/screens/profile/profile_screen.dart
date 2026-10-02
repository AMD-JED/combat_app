import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../models/training_session_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sports_provider.dart';
import '../../services/training_service.dart';
import '../feed/widgets/feed_helpers.dart' show formatRelativeTime;
import 'widgets/profile_labels.dart';

/// The signed-in athlete's own profile — a Flutter port of the prototype's
/// `ProfileScreen.tsx`, scoped to what the backend actually backs:
///
///  * kept: avatar, name, coach badge, bio, multi-sport chips (already real,
///    via [sportProfilesProvider]), wins/losses/draws, sport + belt/rank,
///    weight class, gym, location, edit/logout actions.
///  * dropped entirely (no backend feature at all): the rank-progress bar,
///    followers/likes counts, the performance chart (biometric mock data),
///    the "sparrings validés" counter, and the Posts/Reposts/Bookmarks/
///    Favorites sub-tabs — none of these exist anywhere in the API.
///  * added for real, but own profile only: a "recent sessions" list from
///    the Training module (`GET /training/sessions`) — the backend has no
///    way to fetch another athlete's training history, so this never
///    appears on [PublicProfileScreen].
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _trainingService = TrainingService();
  late final Future<List<TrainingSessionModel>> _sessionsFuture =
      _trainingService.getMySessions(limit: 3);

  Future<void> _confirmLogout() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.logoutConfirmTitle),
        content: Text(l10n.logoutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
            child: Text(l10n.logoutConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final user = ref.watch(authProvider).user;
    final sportProfiles = ref.watch(sportProfilesProvider);

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profileTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.settingsTooltip,
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          // ---------------------------------------------------- avatar
          Center(
            child: Container(
              width: 96,
              height: 96,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent, width: 2),
                boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.30), blurRadius: 16)],
              ),
              child: ClipOval(
                child: user.avatarUrl != null
                    ? CachedNetworkImage(imageUrl: user.avatarUrl!, fit: BoxFit.cover)
                    : Container(
                        color: theme.colorScheme.surface,
                        child: Icon(Icons.person, size: 44, color: theme.colorScheme.onSurfaceVariant),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ------------------------------------------------- name/handle
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    user.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (user.isCoach) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(l10n.coachBadge),
                    backgroundColor: accent.withValues(alpha: 0.15),
                    labelStyle: TextStyle(color: accent, fontWeight: FontWeight.bold),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
          Center(
            child: Text('@${user.username}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),

          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(user.bio!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ],

          // ------------------------------------------------ sport chips
          if (sportProfiles.profiles.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in sportProfiles.profiles)
                  Chip(
                    avatar: Icon(Icons.sports_outlined, size: 16, color: accent),
                    label: Text(p.sport.name),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],

          const SizedBox(height: 18),

          // ------------------------------------------------------ stats
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatColumn(value: user.wins, label: l10n.winsLabel, color: const Color(0xFF22C55E)),
                _StatColumn(value: user.losses, label: l10n.lossesLabel, color: theme.colorScheme.error),
                _StatColumn(
                  value: user.draws,
                  label: l10n.drawsLabel,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ------------------------------------------------ edit / logout
          Row(
            children: [
              Expanded(
                child: _ActionPill(
                  icon: Icons.edit_outlined,
                  label: l10n.editProfileTooltip,
                  color: accent,
                  onTap: () => context.push('/profile/edit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionPill(
                  icon: Icons.logout,
                  label: l10n.logoutTooltip,
                  color: theme.colorScheme.error,
                  onTap: _confirmLogout,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ------------------------------------------------- level & rank
          Text(l10n.levelSectionTitle,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.military_tech_outlined, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sportTypeLabel(l10n, user.sportType),
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      if (user.beltRank != null && user.beltRank!.isNotEmpty)
                        Text(user.beltRank!,
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          _InfoTile(
            icon: Icons.monitor_weight_outlined,
            label: l10n.weightLabel,
            value: weightClassLabel(l10n, user.weightClass),
          ),
          _InfoTile(icon: Icons.fitness_center, label: l10n.gymLabel, value: user.gymAffiliation ?? '—'),
          _InfoTile(
              icon: Icons.location_on_outlined, label: l10n.locationLabel, value: user.location ?? '—'),

          const SizedBox(height: 24),

          // ---------------------------------------------- recent sessions
          Text(l10n.recentSessionsTitle,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          FutureBuilder<List<TrainingSessionModel>>(
            future: _sessionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (snapshot.hasError) {
                return Text(l10n.recentSessionsLoadError,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13));
              }
              final sessions = snapshot.data!;
              if (sessions.isEmpty) {
                return Text(l10n.recentSessionsEmpty,
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontStyle: FontStyle.italic));
              }
              return Column(
                children: [
                  for (final s in sessions) _SessionTile(session: s, accent: accent, l10n: l10n),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  const _StatColumn({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionPill({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final TrainingSessionModel session;
  final Color accent;
  final AppLocalizations l10n;
  const _SessionTile({required this.session, required this.accent, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trainingSessionTypeLabel(l10n, session.sessionType),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${l10n.sessionDurationMinutes(session.durationMinutes)} · '
                  '${formatRelativeTime(l10n, session.sessionDate)}',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          if (session.intensity != null) _IntensityDots(level: session.intensity!, accent: accent),
        ],
      ),
    );
  }
}

/// Five small dots, [level] of them filled — a compact stand-in for a text
/// label across 5 discrete levels without needing 5 more translated strings.
class _IntensityDots extends StatelessWidget {
  final int level;
  final Color accent;
  const _IntensityDots({required this.level, required this.accent});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.25);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: i <= level ? accent : muted),
            ),
          ),
      ],
    );
  }
}
