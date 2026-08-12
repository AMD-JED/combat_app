import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/message_service.dart';
import '../../services/user_service.dart';

/// GET /users/{username} → UserPublicResponse.
/// Used whenever the person taps another athlete's name/avatar — e.g. from
/// a post's author in the feed, a search result, or a follower list.
/// Shows a "مراسلة" (Message) button that opens/creates the DM conversation
/// then navigates straight into the chat screen.
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
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
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
                    child: Text(_error!, style: const TextStyle(color: AppTheme.primaryRed)),
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
                          backgroundColor: AppTheme.surface,
                          backgroundImage: _user!.avatarUrl != null
                              ? CachedNetworkImageProvider(_user!.avatarUrl!)
                              : null,
                          child: _user!.avatarUrl == null
                              ? const Icon(Icons.person, size: 52, color: AppTheme.textMuted)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(_user!.fullName,
                            style: Theme.of(context).textTheme.headlineSmall),
                      ),
                      Center(
                        child: Text('@${_user!.username}',
                            style: const TextStyle(color: AppTheme.textMuted)),
                      ),
                      if (_user!.isCoach) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: Chip(
                            label: const Text('مدرّب'),
                            backgroundColor: AppTheme.gold.withValues(alpha: 0.15),
                            labelStyle: const TextStyle(color: AppTheme.gold),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _Stat(value: '${_user!.wins}', label: 'فوز', color: Colors.green),
                          _Stat(value: '${_user!.losses}', label: 'خسارة', color: AppTheme.primaryRed),
                          _Stat(value: '${_user!.draws}', label: 'تعادل', color: AppTheme.textMuted),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // 🚫 No message button on your own profile.
                      if (!isMe)
                        ElevatedButton.icon(
                          onPressed: _isOpeningChat ? null : _openConversation,
                          icon: _isOpeningChat
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.chat_bubble_outline),
                          label: const Text('مراسلة'),
                        ),

                      const SizedBox(height: 20),
                      _InfoTile(icon: Icons.sports_kabaddi, label: 'الرياضة',
                          value: _user!.sportType?.value ?? '—'),
                      _InfoTile(icon: Icons.monitor_weight_outlined, label: 'الوزن',
                          value: _user!.weightClass?.value ?? '—'),
                      _InfoTile(icon: Icons.military_tech_outlined, label: 'الحزام/الرتبة',
                          value: _user!.beltRank ?? '—'),
                      _InfoTile(icon: Icons.fitness_center, label: 'النادي',
                          value: _user!.gymAffiliation ?? '—'),
                      _InfoTile(icon: Icons.location_on_outlined, label: 'الموقع',
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
    return Column(
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: color, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
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
    return ListTile(
      leading: Icon(icon, color: AppTheme.gold),
      title: Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      subtitle: Text(value, style: const TextStyle(fontSize: 16)),
    );
  }
}
