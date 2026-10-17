import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../models/reel_model.dart';
import '../../models/sport_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/reels_provider.dart';
import '../../providers/sports_provider.dart';
import 'widgets/reel_page.dart';

/// The Reels tab (prototype `ReelsScreen.tsx`): a full-screen vertical pager
/// of short videos with a sport filter on top.
///
/// The tab lives in an `IndexedStack`, so it stays alive while hidden;
/// [isActive] tells it when it is actually on screen (loads the feed the
/// first time, and pauses the video when the person leaves the tab).
class ReelsScreen extends ConsumerStatefulWidget {
  final bool isActive;

  const ReelsScreen({super.key, required this.isActive});

  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen> {
  static const int _prefetchAhead = 3;

  final PageController _pageController = PageController();
  int _index = 0;
  bool _muted = true; // browsers only autoplay muted video
  bool _covered = false; // a profile / dialog is on top of the reels

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      Future.microtask(() => ref.read(reelsProvider.notifier).ensureLoaded());
    }
  }

  @override
  void didUpdateWidget(ReelsScreen old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      ref.read(reelsProvider.notifier).ensureLoaded();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _jumpToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _index = 0;
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      setState(() {});
    });
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    final count = ref.read(reelsProvider).reels.length;
    if (i >= count - _prefetchAhead) ref.read(reelsProvider.notifier).loadMore();
  }

  void _go(int delta) {
    final count = ref.read(reelsProvider).reels.length;
    final target = _index + delta;
    if (target < 0 || target >= count) return;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openProfile(String username) async {
    setState(() => _covered = true);
    await context.push('/u/$username');
    if (!mounted) return;
    setState(() => _covered = false);
  }

  Future<void> _openCreate() async {
    setState(() => _covered = true);
    await context.push('/reels/create');
    if (!mounted) return;
    setState(() => _covered = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = Theme.of(context).colorScheme.primary;
    final state = ref.watch(reelsProvider);
    final myId = ref.watch(authProvider.select((s) => s.user?.id));
    final sports = [
      for (final s in ref.watch(sportsListProvider).valueOrNull ?? const <SportModel>[])
        if (s.isActive) s,
    ];

    // A new first item (a reel was just published) or a new filter: go back
    // to the top of the pager.
    ref.listen<ReelsState>(reelsProvider, (prev, next) {
      if (prev == null) return;
      final filterChanged = prev.sportId != next.sportId;
      final newTop = prev.reels.isNotEmpty &&
          next.reels.isNotEmpty &&
          prev.reels.first.id != next.reels.first.id;
      if (filterChanged || newTop) _jumpToTop();
    });

    final reels = state.reels;
    final index = reels.isEmpty ? 0 : (_index < reels.length ? _index : reels.length - 1);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final topInset = MediaQuery.paddingOf(context).top;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildBody(l10n, state, reels, index, myId, sports),

              // ── top bar: filters + create ───────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.fromLTRB(12, topInset + 8, 12, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _FilterPill(
                                label: l10n.reelsForYou,
                                selected: state.sportId == null,
                                accent: accent,
                                onTap: () => ref.read(reelsProvider.notifier).setSport(null),
                              ),
                              for (final sport in sports)
                                _FilterPill(
                                  label: sport.name,
                                  selected: state.sportId == sport.id,
                                  accent: accent,
                                  onTap: () => ref.read(reelsProvider.notifier).setSport(sport.id),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: l10n.reelsCreateTooltip,
                        child: InkResponse(
                          onTap: _openCreate,
                          radius: 22,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0x33FFFFFF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.add, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── desktop up / down arrows ────────────────────────────
              if (wide && reels.isNotEmpty)
                PositionedDirectional(
                  start: 10,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ArrowButton(icon: Icons.keyboard_arrow_up, onTap: () => _go(-1)),
                        const SizedBox(height: 8),
                        _ArrowButton(icon: Icons.keyboard_arrow_down, onTap: () => _go(1)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    AppLocalizations l10n,
    ReelsState state,
    List<ReelModel> reels,
    int index,
    int? myId,
    List<SportModel> sports,
  ) {
    if (state.isLoading && reels.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (reels.isEmpty) {
      final failed = state.errorMessage != null;
      final filtered = state.sportId != null;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                failed ? Icons.cloud_off_outlined : Icons.movie_outlined,
                color: Colors.white38,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                failed
                    ? l10n.reelsLoadError
                    : (filtered ? l10n.reelsEmptyFilter : l10n.reelsEmptyTitle),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (!failed && !filtered) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.reelsEmptySubtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              if (failed)
                OutlinedButton(
                  onPressed: () => ref.read(reelsProvider.notifier).fetch(),
                  child: Text(l10n.retryButton),
                )
              else if (filtered)
                OutlinedButton(
                  onPressed: () => ref.read(reelsProvider.notifier).setSport(null),
                  child: Text(l10n.reelsShowAll),
                )
              else
                FilledButton.icon(
                  onPressed: _openCreate,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.reelsCreateTooltip),
                ),
            ],
          ),
        ),
      );
    }

    final sportNames = {for (final s in sports) s.id: s.name};

    return ScrollConfiguration(
      // Lets a mouse drag the pager too (web / desktop only react to touch
      // by default).
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
      ),
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: reels.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, i) {
          final reel = state.reels[i];
          return ReelPage(
            key: ValueKey(reel.id),
            reel: reel,
            sportName: sportNames[reel.sportId],
            selected: i == index,
            playing: widget.isActive && !_covered,
            muted: _muted,
            isMine: reel.author.id == myId,
            onToggleMute: () => setState(() => _muted = !_muted),
            onOverlayChanged: (v) => setState(() => _covered = v),
            onOpenProfile: _openProfile,
          );
        },
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? accent : const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
