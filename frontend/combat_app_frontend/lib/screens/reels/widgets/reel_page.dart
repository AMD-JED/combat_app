import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/reel_model.dart';
import '../../../providers/reels_provider.dart';
import '../../feed/widgets/feed_helpers.dart';
import '../../messages/widgets/chat_helpers.dart' show videoPosterUrl;
import 'reel_comments_sheet.dart';

/// One full-screen reel: the video, the right-hand action bar and the
/// author / caption footer (prototype `ReelsScreen.tsx`).
///
/// Only the page the user is on ([selected]) owns a video controller; the
/// neighbours show their poster frame, so at most one video is in memory.
/// [playing] is false while the tab is hidden or something is on top of the
/// reels (profile, dialog), which pauses the video without tearing it down.
class ReelPage extends ConsumerStatefulWidget {
  final ReelModel reel;
  final String? sportName;
  final bool selected;
  final bool playing;
  final bool muted;
  final bool isMine;
  final VoidCallback onToggleMute;
  final ValueChanged<bool> onOverlayChanged;
  final ValueChanged<String> onOpenProfile;

  const ReelPage({
    super.key,
    required this.reel,
    required this.sportName,
    required this.selected,
    required this.playing,
    required this.muted,
    required this.isMine,
    required this.onToggleMute,
    required this.onOverlayChanged,
    required this.onOpenProfile,
  });

  @override
  ConsumerState<ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends ConsumerState<ReelPage> {
  VideoPlayerController? _video;
  bool _ready = false;
  bool _failed = false;
  bool _userPaused = false;
  bool _showHeart = false;
  Timer? _heartTimer;
  int _initToken = 0;

  @override
  void initState() {
    super.initState();
    if (widget.selected) _initVideo();
  }

  @override
  void didUpdateWidget(ReelPage old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) {
      _userPaused = false;
      _initVideo();
    } else if (!widget.selected && old.selected) {
      _disposeVideo();
    }
    if (widget.muted != old.muted) _video?.setVolume(widget.muted ? 0 : 1);
    _syncPlayback();
  }

  @override
  void dispose() {
    _heartTimer?.cancel();
    _disposeVideo();
    super.dispose();
  }

  Future<void> _initVideo() async {
    // Counts the view once per reel per session (the provider dedups).
    ref.read(reelsProvider.notifier).markViewed(widget.reel.id);
    final token = ++_initToken;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.reel.mediaUrl));
    _video = controller;
    _ready = false;
    _failed = false;
    try {
      await controller.initialize();
      if (!mounted || token != _initToken) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(widget.muted ? 0 : 1);
      if (!mounted || token != _initToken) {
        await controller.dispose();
        return;
      }
      setState(() => _ready = true);
      _syncPlayback();
    } catch (_) {
      if (!mounted || token != _initToken) {
        await controller.dispose();
        return;
      }
      if (_video == controller) _video = null;
      await controller.dispose();
      setState(() => _failed = true);
    }
  }

  void _disposeVideo() {
    _initToken++; // cancels an initialisation still in flight
    final controller = _video;
    _video = null;
    _ready = false;
    controller?.dispose();
  }

  void _syncPlayback() {
    final controller = _video;
    if (controller == null || !_ready) return;
    final shouldPlay = widget.selected && widget.playing && !_userPaused;
    if (shouldPlay && !controller.value.isPlaying) {
      controller.play();
    } else if (!shouldPlay && controller.value.isPlaying) {
      controller.pause();
    }
  }

  void _togglePlay() {
    if (!_ready) return;
    setState(() => _userPaused = !_userPaused);
    _syncPlayback();
  }

  void _doubleTapLike() {
    if (!widget.reel.likedByMe) {
      ref.read(reelsProvider.notifier).toggleLike(widget.reel.id);
    }
    _heartTimer?.cancel();
    setState(() => _showHeart = true);
    _heartTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  Future<void> _openComments() async {
    // Comments keep the video playing (like the prototype); only the keyboard
    // and sheet share the screen.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ReelCommentsSheet(reelId: widget.reel.id),
    );
  }

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    // The direct video link: unlike the app address it opens the clip itself
    // on every platform (there is no per-reel route in the app).
    await Clipboard.setData(ClipboardData(text: widget.reel.mediaUrl));
    messenger.showSnackBar(SnackBar(content: Text(l10n.reelsLinkCopied)));
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    widget.onOverlayChanged(true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.reelDeleteConfirmTitle),
        content: Text(l10n.postDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    widget.onOverlayChanged(false);
    if (confirmed != true || !mounted) return;
    final ok = await ref.read(reelsProvider.notifier).delete(widget.reel.id);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.reelDeleteFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accent = Theme.of(context).colorScheme.primary;
    final reel = widget.reel;
    final controller = _video;

    final poster = (reel.thumbnailUrl != null && reel.thumbnailUrl!.isNotEmpty)
        ? reel.thumbnailUrl!
        : videoPosterUrl(reel.mediaUrl);

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── media ────────────────────────────────────────────────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlay,
            onDoubleTap: _doubleTapLike,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (poster.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: poster,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                if (_ready && controller != null)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                if (widget.selected && !_ready && !_failed)
                  const Center(child: CircularProgressIndicator(color: Colors.white)),
                if (_failed)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          l10n.reelsVideoError,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                if (_userPaused && _ready)
                  const Center(
                    child: _RoundIcon(icon: Icons.play_arrow_rounded, size: 64, iconSize: 40),
                  ),
                IgnorePointer(
                  child: Center(
                    child: AnimatedScale(
                      scale: _showHeart ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutBack,
                      child: AnimatedOpacity(
                        opacity: _showHeart ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.favorite, color: Colors.redAccent, size: 110),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── bottom gradient + footer ─────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: 260,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xE6000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            start: 16,
            end: 84,
            bottom: 22,
            child: _Footer(
              reel: reel,
              sportName: widget.sportName,
              isMine: widget.isMine,
              accent: accent,
              onOpenProfile: () => widget.onOpenProfile(reel.author.username),
              onToggleFollow: () =>
                  ref.read(reelsProvider.notifier).toggleFollow(reel.author.id),
            ),
          ),

          // ── right action bar ─────────────────────────────────────────
          PositionedDirectional(
            end: 12,
            bottom: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AuthorBubble(
                  reel: reel,
                  isMine: widget.isMine,
                  accent: accent,
                  onOpenProfile: () => widget.onOpenProfile(reel.author.username),
                  onFollow: () => ref.read(reelsProvider.notifier).toggleFollow(reel.author.id),
                ),
                const SizedBox(height: 18),
                _Action(
                  icon: reel.likedByMe ? Icons.favorite : Icons.favorite_border,
                  color: reel.likedByMe ? Colors.redAccent : Colors.white,
                  label: formatCount(reel.likesCount),
                  onTap: () => ref.read(reelsProvider.notifier).toggleLike(reel.id),
                ),
                const SizedBox(height: 14),
                _Action(
                  icon: Icons.chat_bubble_outline,
                  label: formatCount(reel.commentsCount),
                  onTap: _openComments,
                ),
                const SizedBox(height: 14),
                _Action(
                  icon: Icons.share_outlined,
                  tooltip: l10n.reelsShareTooltip,
                  onTap: _share,
                ),
                const SizedBox(height: 14),
                _Action(
                  icon: widget.muted ? Icons.volume_off : Icons.volume_up,
                  color: widget.muted ? Colors.white : Colors.greenAccent,
                  tooltip: widget.muted ? l10n.reelsUnmuteTooltip : l10n.reelsMuteTooltip,
                  onTap: widget.onToggleMute,
                ),
                if (widget.isMine) ...[
                  const SizedBox(height: 14),
                  _Action(
                    icon: Icons.delete_outline,
                    tooltip: l10n.reelDeleteAction,
                    onTap: _confirmDelete,
                  ),
                ],
              ],
            ),
          ),

          // ── thin progress line ───────────────────────────────────────
          if (_ready && controller != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: false,
                padding: EdgeInsets.zero,
                colors: VideoProgressColors(
                  playedColor: accent,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;

  const _RoundIcon({required this.icon, required this.size, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? label;
  final String? tooltip;
  final VoidCallback onTap;

  const _Action({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
    this.label,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = InkResponse(
      onTap: onTap,
      radius: 28,
      child: Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 26),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tooltip == null ? button : Tooltip(message: tooltip!, child: button),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(
            label!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
          ),
        ],
      ],
    );
  }
}

class _AuthorBubble extends StatelessWidget {
  final ReelModel reel;
  final bool isMine;
  final Color accent;
  final VoidCallback onOpenProfile;
  final VoidCallback onFollow;

  const _AuthorBubble({
    required this.reel,
    required this.isMine,
    required this.accent,
    required this.onOpenProfile,
    required this.onFollow,
  });

  @override
  Widget build(BuildContext context) {
    final showPlus = !isMine && !reel.followingAuthor;
    return SizedBox(
      width: 52,
      height: 58,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          GestureDetector(
            onTap: onOpenProfile,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: RoundedAvatar(url: reel.author.avatarUrl, accent: accent, size: 46),
            ),
          ),
          if (showPlus)
            Positioned(
              bottom: 0,
              child: GestureDetector(
                onTap: onFollow,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final ReelModel reel;
  final String? sportName;
  final bool isMine;
  final Color accent;
  final VoidCallback onOpenProfile;
  final VoidCallback onToggleFollow;

  const _Footer({
    required this.reel,
    required this.sportName,
    required this.isMine,
    required this.accent,
    required this.onOpenProfile,
    required this.onToggleFollow,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const shadow = [Shadow(blurRadius: 4, color: Colors.black54)];
    final caption = reel.caption?.trim() ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GestureDetector(
              onTap: onOpenProfile,
              child: Text(
                reel.author.fullName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  shadows: shadow,
                ),
              ),
            ),
            Text(
              '@${reel.author.username}',
              style: const TextStyle(color: Colors.white70, fontSize: 12, shadows: shadow),
            ),
            if (reel.isCoachContent) _Chip(label: l10n.reelsCoachBadge, color: Colors.amber.shade700),
            if (sportName != null) _Chip(label: sportName!, color: accent),
            if (!isMine)
              GestureDetector(
                onTap: onToggleFollow,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: reel.followingAuthor ? Colors.white24 : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: reel.followingAuthor ? Border.all(color: Colors.white38) : null,
                  ),
                  child: Text(
                    reel.followingAuthor ? l10n.followingButton : l10n.followButton,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: reel.followingAuthor ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.35,
              shadows: shadow,
            ),
          ),
        ],
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;

  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}
