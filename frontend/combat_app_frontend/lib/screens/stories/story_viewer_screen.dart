import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../models/story_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stories_provider.dart';
import '../feed/widgets/feed_helpers.dart';
import '../messages/widgets/chat_helpers.dart' show videoPosterUrl;

/// Route argument for `/stories/view`.
class StoryViewerArgs {
  final int groupIndex;
  const StoryViewerArgs({required this.groupIndex});
}

/// Full-screen story viewer — Flutter port of the prototype's
/// `StoryViewerModal.tsx` (segmented progress bars, tap zones, pause, reply
/// field, heart) plus what the backend supports on top: video stories, text
/// stories, captions, the author's "seen by" list and deleting a story.
///
/// The viewer plays through the authors in the order the rail showed them
/// (it snapshots the story ids when it opens) and always reads the latest
/// version of each story from [storiesProvider], so likes/views stay live.
class StoryViewerScreen extends ConsumerStatefulWidget {
  final int initialGroupIndex;
  const StoryViewerScreen({super.key, required this.initialGroupIndex});

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _imageDuration = Duration(seconds: 5);

  late final List<List<int>> _order;
  late final AnimationController _timer;
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocus = FocusNode();

  int _groupIndex = 0;
  int _storyIndex = 0;
  VideoPlayerController? _video;
  int _startToken = 0;
  bool _advancing = false;

  bool _held = false; // finger held down on the story
  bool _manualPause = false; // pause button
  bool _inputFocused = false; // typing a reply
  bool _sheetOpen = false; // viewers sheet / dialog open

  @override
  void initState() {
    super.initState();
    final groups = ref.read(storiesProvider).groups;
    _order = groups.map((g) => g.stories.map((s) => s.id).toList()).toList();

    _timer = AnimationController(vsync: this, duration: _imageDuration)
      ..addListener(() => _progress.value = _timer.value)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });

    _replyFocus.addListener(() {
      _inputFocused = _replyFocus.hasFocus;
      _updatePlayback();
    });

    if (_order.isEmpty ||
        widget.initialGroupIndex < 0 ||
        widget.initialGroupIndex >= _order.length) {
      // Nothing to show (e.g. the page was reloaded on this route).
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      return;
    }
    _groupIndex = widget.initialGroupIndex;
    _storyIndex = groups[_groupIndex].firstUnseenIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) => _startStory());
  }

  @override
  void dispose() {
    _startToken++;
    _timer.dispose();
    _progress.dispose();
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    _replyController.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  // ── navigation ───────────────────────────────────────────

  void _close() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main');
    }
  }

  void _next() {
    if (!mounted) return;
    if (_storyIndex < _order[_groupIndex].length - 1) {
      setState(() => _storyIndex++);
    } else if (_groupIndex < _order.length - 1) {
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
    } else {
      _close();
      return;
    }
    _startStory();
  }

  void _previous() {
    if (!mounted) return;
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
    } else if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _storyIndex = 0;
      });
    }
    // On the very first story this simply restarts it.
    _startStory();
  }

  StoryModel? _currentStory() {
    if (_groupIndex >= _order.length) return null;
    final ids = _order[_groupIndex];
    if (_storyIndex >= ids.length) return null;
    return ref.read(storiesProvider).storyById(ids[_storyIndex]);
  }

  // ── playback ─────────────────────────────────────────────

  Future<void> _startStory() async {
    final token = ++_startToken;
    _advancing = false;
    _timer.stop();
    _timer.value = 0;
    _progress.value = 0;

    final old = _video;
    _video = null;
    old?.removeListener(_onVideoTick);
    await old?.dispose();
    if (!mounted || token != _startToken) return;

    final story = _currentStory();
    if (story == null) {
      // Deleted meanwhile — move on.
      _next();
      return;
    }

    ref.read(storiesProvider.notifier).markViewed(story.id);
    _precacheNext();

    if (story.contentType == StoryContentType.video && story.mediaUrl != null) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(story.mediaUrl!));
      _video = controller;
      if (mounted) setState(() {});
      try {
        await controller.initialize();
        if (!mounted || token != _startToken) {
          if (_video == controller) _video = null;
          await controller.dispose();
          return;
        }
        await controller.setLooping(false);
        controller.addListener(_onVideoTick);
        if (mounted) setState(() {});
        _updatePlayback();
      } catch (_) {
        // The video couldn't load: show the error state for a while, then
        // continue like an image story.
        if (!mounted || token != _startToken) return;
        _video = null;
        await controller.dispose();
        if (!mounted || token != _startToken) return;
        setState(() {});
        _updatePlayback(forceTimer: true);
      }
      return;
    }

    _updatePlayback();
  }

  void _onVideoTick() {
    final video = _video;
    if (video == null || !mounted) return;
    final value = video.value;
    if (!value.isInitialized) return;
    final total = value.duration.inMilliseconds;
    if (total <= 0) return;
    final done = value.position.inMilliseconds / total;
    _progress.value = done > 1 ? 1.0 : done;
    if (value.position.inMilliseconds >= total - 80 && !_advancing) {
      _advancing = true;
      _next();
    }
  }

  bool get _paused => _held || _manualPause || _inputFocused || _sheetOpen;

  /// Applies the current pause state to whatever drives the progress: the
  /// video (when there is a loaded one) or the 5-second timer.
  void _updatePlayback({bool forceTimer = false}) {
    if (!mounted) return;
    final story = _currentStory();
    if (story == null) return;
    final video = _video;

    if (!forceTimer && video != null && video.value.isInitialized) {
      if (_paused) {
        video.pause();
      } else {
        video.play().catchError((_) {});
      }
      return;
    }

    // Image / text story — or a video that is still loading / failed.
    final waitingForVideo = !forceTimer &&
        story.contentType == StoryContentType.video &&
        video != null;
    if (waitingForVideo) return; // the loading spinner covers it
    if (_paused) {
      _timer.stop();
    } else if (!_timer.isCompleted) {
      _timer.forward();
    }
  }

  void _precacheNext() {
    if (_groupIndex >= _order.length) return;
    int? nextId;
    if (_storyIndex < _order[_groupIndex].length - 1) {
      nextId = _order[_groupIndex][_storyIndex + 1];
    } else if (_groupIndex < _order.length - 1 && _order[_groupIndex + 1].isNotEmpty) {
      nextId = _order[_groupIndex + 1].first;
    }
    if (nextId == null) return;
    final next = ref.read(storiesProvider).storyById(nextId);
    if (next != null &&
        next.contentType == StoryContentType.image &&
        next.mediaUrl != null) {
      precacheImage(CachedNetworkImageProvider(next.mediaUrl!), context);
    }
  }

  // ── actions ──────────────────────────────────────────────

  void _togglePause() {
    setState(() => _manualPause = !_manualPause);
    _updatePlayback();
  }

  Future<void> _sendReply(StoryModel story) async {
    final l10n = AppLocalizations.of(context)!;
    final text = _replyController.text;
    if (text.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    _replyController.clear();
    _replyFocus.unfocus();
    final conversationId =
        await ref.read(storiesProvider.notifier).reply(story.id, text);
    if (conversationId == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.storyReplyFailed)));
      return;
    }
    // A SnackBar that has an action never times out by itself in recent
    // Flutter versions, and the messenger lives above the router, so it would
    // follow the user into every screen. Close it ourselves.
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.storyReplySent),
        // The reply is a private message: tell the user where it went.
        action: mounted
            ? SnackBarAction(
                label: l10n.storyReplyOpenChat,
                onPressed: () => _openChat(conversationId, story.author),
              )
            : null,
      ),
    );
    var closed = false;
    controller.closed.then((_) => closed = true);
    Timer(const Duration(seconds: 6), () {
      if (!closed) controller.close();
    });
  }

  /// Opens the conversation with the story's author on top of the viewer,
  /// pausing the story meanwhile.
  Future<void> _openChat(int conversationId, UserModel author) async {
    if (!mounted) return;
    setState(() => _sheetOpen = true);
    _updatePlayback();
    await context.push('/messages/$conversationId', extra: author);
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    _updatePlayback();
  }

  Future<void> _confirmDelete(StoryModel story) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _sheetOpen = true);
    _updatePlayback();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.storyDeleteTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.deleteButton,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    var deleted = false;
    if (confirmed == true) {
      deleted = await ref.read(storiesProvider.notifier).delete(story.id);
      if (!mounted) return;
      if (!deleted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.storyDeleteFailed)));
      }
    }
    setState(() => _sheetOpen = false);
    if (deleted) {
      _next(); // the id is gone from the provider; _startStory skips it
    } else {
      _updatePlayback();
    }
  }

  Future<void> _showViewers(StoryModel story) async {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(storiesProvider.notifier);
    setState(() => _sheetOpen = true);
    _updatePlayback();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.storyViewersTitle,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: FutureBuilder<List<StoryViewer>>(
                future: notifier.loadViewers(story.id),
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text(l10n.feedLoadError));
                  }
                  final viewers = snapshot.data ?? const <StoryViewer>[];
                  if (viewers.isEmpty) {
                    return Center(child: Text(l10n.storyNoViewers));
                  }
                  return ListView.builder(
                    itemCount: viewers.length,
                    itemBuilder: (ctx, i) {
                      final v = viewers[i];
                      final url = v.viewer.avatarUrl;
                      final hasUrl = url != null && url.isNotEmpty;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              hasUrl ? CachedNetworkImageProvider(url) : null,
                          child: hasUrl ? null : const Icon(Icons.person),
                        ),
                        title: Text(v.viewer.fullName),
                        subtitle: Text('@${v.viewer.username}'),
                        trailing: Text(
                          formatRelativeTime(l10n, v.viewedAt),
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    _updatePlayback();
  }

  // ── build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final stories = ref.watch(storiesProvider);
    final myId = ref.watch(authProvider.select((s) => s.user?.id));

    if (_order.isEmpty || _groupIndex >= _order.length) {
      return const Scaffold(backgroundColor: Colors.black);
    }
    final ids = _order[_groupIndex];
    final story = _storyIndex < ids.length ? stories.storyById(ids[_storyIndex]) : null;
    if (story == null) {
      // Transient: the story was just deleted and _startStory is skipping it.
      return const Scaffold(backgroundColor: Colors.black);
    }
    final isMine = story.author.id == myId;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _StoryMedia(story: story, video: _video),
              _TapZones(
                onPrevious: _previous,
                onNext: _next,
                onHoldChanged: (held) {
                  _held = held;
                  _updatePlayback();
                },
                onSwipeDown: _close,
              ),
              // Top gradient so the white header stays readable on any media.
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 140,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xAA000000), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: _ProgressBars(
                        count: ids.length,
                        current: _storyIndex,
                        progress: _progress,
                        color: accent,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
                      child: _Header(
                        story: story,
                        isPaused: _manualPause,
                        onTogglePause: _togglePause,
                        onClose: _close,
                      ),
                    ),
                    const Spacer(),
                    if (story.hasCaption && story.contentType != StoryContentType.text)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            story.textContent!,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: isMine
                          ? _OwnerBar(
                              story: story,
                              l10n: l10n,
                              onViewers: () => _showViewers(story),
                              onDelete: () => _confirmDelete(story),
                            )
                          : _ReplyBar(
                              story: story,
                              l10n: l10n,
                              controller: _replyController,
                              focusNode: _replyFocus,
                              onSend: () => _sendReply(story),
                              onLike: () =>
                                  ref.read(storiesProvider.notifier).toggleLike(story.id),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────
//  Pieces
// ──────────────────────────────────────────────────────────

/// Left/right thirds go back/forward (mirrored in RTL: the start side is
/// "previous"), holding pauses, swiping down closes.
class _TapZones extends StatelessWidget {
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<bool> onHoldChanged;
  final VoidCallback onSwipeDown;

  const _TapZones({
    required this.onPrevious,
    required this.onNext,
    required this.onHoldChanged,
    required this.onSwipeDown,
  });

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final x = isRtl ? width - details.localPosition.dx : details.localPosition.dx;
            if (x < width / 3) {
              onPrevious();
            } else {
              onNext();
            }
          },
          onLongPressStart: (_) => onHoldChanged(true),
          onLongPressEnd: (_) => onHoldChanged(false),
          onLongPressCancel: () => onHoldChanged(false),
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 400) onSwipeDown();
          },
        );
      },
    );
  }
}

class _ProgressBars extends StatelessWidget {
  final int count;
  final int current;
  final ValueNotifier<double> progress;
  final Color color;

  const _ProgressBars({
    required this.count,
    required this.current,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.white24),
                    if (i < current)
                      ColoredBox(color: color)
                    else if (i == current)
                      ValueListenableBuilder<double>(
                        valueListenable: progress,
                        builder: (context, value, _) => FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: value < 0 ? 0 : (value > 1 ? 1 : value),
                          child: ColoredBox(color: color),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Header extends StatelessWidget {
  final StoryModel story;
  final bool isPaused;
  final VoidCallback onTogglePause;
  final VoidCallback onClose;

  const _Header({
    required this.story,
    required this.isPaused,
    required this.onTogglePause,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final url = story.author.avatarUrl;
    final hasUrl = url != null && url.isNotEmpty;

    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.white24,
          backgroundImage: hasUrl ? CachedNetworkImageProvider(url) : null,
          child: hasUrl ? null : const Icon(Icons.person, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                story.author.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              Text(
                formatRelativeTime(l10n, story.createdAt),
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onTogglePause,
          icon: Icon(isPaused ? Icons.play_arrow : Icons.pause, color: Colors.white),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close, color: Colors.white),
        ),
      ],
    );
  }
}

/// Reply field + heart (someone else's story).
class _ReplyBar extends StatelessWidget {
  final StoryModel story;
  final AppLocalizations l10n;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onLike;

  const _ReplyBar({
    required this.story,
    required this.l10n,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            maxLength: 1000,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
            decoration: InputDecoration(
              hintText: l10n.storyReplyHint(story.author.fullName),
              hintStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(26),
                borderSide: const BorderSide(color: Colors.white38),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(26),
                borderSide: const BorderSide(color: Colors.white38),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(26),
                borderSide: const BorderSide(color: Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor:
                story.likedByMe ? const Color(0xFFF43F5E) : Colors.white.withValues(alpha: 0.18),
            foregroundColor: Colors.white,
          ),
          onPressed: onLike,
          icon: Icon(story.likedByMe ? Icons.favorite : Icons.favorite_border),
        ),
      ],
    );
  }
}

/// Views / likes / delete (my own story).
class _OwnerBar extends StatelessWidget {
  final StoryModel story;
  final AppLocalizations l10n;
  final VoidCallback onViewers;
  final VoidCallback onDelete;

  const _OwnerBar({
    required this.story,
    required this.l10n,
    required this.onViewers,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton.icon(
          onPressed: onViewers,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          icon: const Icon(Icons.visibility_outlined, size: 20),
          label: Text(l10n.storyViewsCount(story.viewsCount)),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.favorite, color: Color(0xFFF43F5E), size: 18),
        const SizedBox(width: 4),
        Text(
          '${story.likesCount}',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline, color: Colors.white),
        ),
      ],
    );
  }
}

/// The story itself: photo, playing video, or colored text card.
class _StoryMedia extends StatelessWidget {
  final StoryModel story;
  final VideoPlayerController? video;

  const _StoryMedia({required this.story, required this.video});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    switch (story.contentType) {
      case StoryContentType.image:
        return story.mediaUrl == null
            ? const _MediaError()
            : CachedNetworkImage(
                imageUrl: story.mediaUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) => const _MediaError(),
              );

      case StoryContentType.video:
        final controller = video;
        if (controller != null && controller.value.isInitialized) {
          final size = controller.value.size;
          return ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: VideoPlayer(controller),
              ),
            ),
          );
        }
        if (controller == null) {
          // Either still starting or the video failed to load.
          final poster = story.mediaUrl == null ? '' : videoPosterUrl(story.mediaUrl!);
          return poster.isEmpty
              ? const _MediaError()
              : CachedNetworkImage(
                  imageUrl: poster,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const _MediaError(),
                );
        }
        return const Center(child: CircularProgressIndicator());

      case StoryContentType.text:
        final bg = story.parsedBackground ?? scheme.primary;
        final fg = bg.computeLuminance() > 0.6 ? Colors.black : Colors.white;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [bg, Color.lerp(bg, Colors.black, 0.35)!],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28),
          alignment: Alignment.center,
          child: Text(
            story.textContent ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
        );
    }
  }
}

class _MediaError extends StatelessWidget {
  const _MediaError();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
          const SizedBox(height: 8),
          Text(
            l10n.storyUnavailable,
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
