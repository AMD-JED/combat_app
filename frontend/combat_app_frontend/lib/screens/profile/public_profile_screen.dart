import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/message_service.dart';
import '../../services/user_service.dart';

/// GET /users/{username} → UserPublicResponse.
/// Used whenever the person taps another athlete's name/avatar — e.g. from
/// a post's author in the feed, a search result, or a follower list.
/// Shows a Message button that opens/creates the DM conversation then
/// navigates straight into the chat screen, and a Follow/Following toggle
/// (this is the only place that exists in the app — the feed only shows
/// posts from people you follow, see `following_ids` in `get_feed`).
class PublicProfileScreen extends ConsumerStatefulWidget {
  final String username;
  const PublicProfileScreen({super.key, required this.username});

  @override
  ConsumerState<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  final _userService = UserService();
  final _messageService = MessageService();

  UserModel? _user;
  bool _isLoading = true;
  bool _isOpeningChat = false;
  bool? _isFollowing; // null until the follow-status check resolves
  bool _isTogglingFollow = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = await _userService.getProfile(widget.username);
      setState(() {
        _user = user;
        _isLoading = false;
      });
      final myId = ref.read(authProvider).user?.id;
      if (myId != null && myId != user.id) {
        // `UserPublicResponse` carries no is_following flag of its own —
        // this is how the current follow state is actually determined.
        final following = await _userService.getFollowing(myId);
        if (mounted) {
          setState(() => _isFollowing = following.any((u) => u.id == user.id));
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleFollow() async {
    final user = _user;
    if (user == null || _isTogglingFollow) return;
    setState(() => _isTogglingFollow = true);
    try {
      final action = await _userService.toggleFollow(user.id);
      if (mounted) {
        setState(() {
          _isFollowing = action == 'followed';
          _isTogglingFollow = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTogglingFollow = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _openConversation() async {
    final user = _user;
    if (user == null) return;
    setState(() => _isOpeningChat = true);
    try {
      final conversationId = await _messageService.openConversation(user.id);
      if (mounted) {
        context.push('/messages/$conversationId', extra: user);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _isOpeningChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final myId = ref.watch(authProvider).user?.id;
    final isMe = _user != null && _user!.id == myId;

    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 52,
                          backgroundColor: theme.colorScheme.surface,
                          backgroundImage: _user!.avatarUrl != null
                              ? CachedNetworkImageProvider(_user!.avatarUrl!)
                              : null,
                          child: _user!.avatarUrl == null
                              ? Icon(Icons.person, size: 52, color: theme.colorScheme.onSurfaceVariant)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(_user!.fullName, style: theme.textTheme.headlineMedium),
                      ),
                      Center(
                        child: Text('@${_user!.username}',
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      if (_user!.isCoach) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: Chip(
                            label: Text(l10n.coachBadge),
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                            labelStyle: TextStyle(color: theme.colorScheme.primary),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _Stat(value: '${_user!.wins}', label: l10n.winsLabel, color: Colors.green),
                          _Stat(
                              value: '${_user!.losses}',
                              label: l10n.lossesLabel,
                              color: theme.colorScheme.error),
                          _Stat(
                              value: '${_user!.draws}',
                              label: l10n.drawsLabel,
                              color: theme.colorScheme.onSurfaceVariant),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // No message/follow buttons on your own profile.
                      if (!isMe)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isTogglingFollow ? null : _toggleFollow,
                                icon: _isTogglingFollow
                                    ? SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: theme.colorScheme.primary),
                                      )
                                    : Icon(_isFollowing == true
                                        ? Icons.check_rounded
                                        : Icons.person_add_alt_1_outlined),
                                label: Text(
                                    _isFollowing == true ? l10n.followingButton : l10n.followButton),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isOpeningChat ? null : _openConversation,
                                icon: _isOpeningChat
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.chat_bubble_outline),
                                label: Text(l10n.messageButton),
                              ),
                            ),
                          ],
                        ),

                      const SizedBox(height: 20),
                      _InfoTile(icon: Icons.sports_kabaddi, label: l10n.sportLabel,
                          value: _user!.sportType?.value ?? '—'),
                      _InfoTile(icon: Icons.monitor_weight_outlined, label: l10n.weightLabel,
                          value: _user!.weightClass?.value ?? '—'),
                      _InfoTile(icon: Icons.military_tech_outlined, label: l10n.beltRankLabel,
                          value: _user!.beltRank ?? '—'),
                      _InfoTile(icon: Icons.fitness_center, label: l10n.gymLabel,
                          value: _user!.gymAffiliation ?? '—'),
                      _InfoTile(icon: Icons.location_on_outlined, label: l10n.locationLabel,
                          value: _user!.location ?? '—'),
                      if (_user!.bio != null && _user!.bio!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(_user!.bio!),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
      ],
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
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
      subtitle: Text(value, style: const TextStyle(fontSize: 16)),
    );
  }
}
