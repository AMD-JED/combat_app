import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الملف الشخصي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push('/profile/edit'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(authProvider.notifier).refreshUser(),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 56,
                      backgroundColor: AppTheme.surface,
                      backgroundImage: user.avatarUrl != null
                          ? CachedNetworkImageProvider(user.avatarUrl!)
                          : null,
                      child: user.avatarUrl == null
                          ? const Icon(Icons.person, size: 56, color: AppTheme.textMuted)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(user.fullName,
                        style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  Center(
                    child: Text('@${user.username}',
                        style: const TextStyle(color: AppTheme.textMuted)),
                  ),
                  if (user.isCoach) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Chip(
                        label: const Text('مدرّب'),
                        backgroundColor: AppTheme.gold.withValues(alpha: 0.15),
                        labelStyle: const TextStyle(color: AppTheme.gold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  _RecordCard(user: user),
                  const SizedBox(height: 16),
                  _InfoTile(icon: Icons.sports_kabaddi, label: 'الرياضة',
                      value: user.sportType?.value ?? '—'),
                  _InfoTile(icon: Icons.monitor_weight_outlined, label: 'وزن',
                      value: user.weightClass?.value ?? '—'),
                  _InfoTile(icon: Icons.military_tech_outlined, label: 'الحزام/الرتبة',
                      value: user.beltRank ?? '—'),
                  _InfoTile(icon: Icons.fitness_center, label: 'النادي',
                      value: user.gymAffiliation ?? '—'),
                  _InfoTile(icon: Icons.location_on_outlined, label: 'الموقع',
                      value: user.location ?? '—'),
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(user.bio!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final UserModel user;
  const _RecordCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _StatColumn(value: '${user.wins}', label: 'فوز', color: Colors.green),
            _StatColumn(value: '${user.losses}', label: 'خسارة', color: AppTheme.primaryRed),
            _StatColumn(value: '${user.draws}', label: 'تعادل', color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatColumn({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: color, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppTheme.textMuted)),
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
