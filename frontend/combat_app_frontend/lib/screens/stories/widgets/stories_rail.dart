import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/story_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/stories_provider.dart';
import '../../messages/widgets/chat_helpers.dart' show videoPosterUrl;
import '../story_viewer_screen.dart';

/// Horizontal stories strip on top of the feed — Flutter port of the
/// prototype's `StoriesRail.tsx`: a "create story" card followed by one
/// 96x160 card per author (preview, avatar ring, name). The ring is accent
/// colored while there is something unseen and muted once everything was
/// watched. The signed-in user's own stories get the first card.
class StoriesRail extends ConsumerWidget {
  const StoriesRail({super.key});

  static const double _cardWidth = 96;
  static const double _cardHeight = 160;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final groups = ref.watch(storiesProvider.select((s) => s.groups));
    final me = ref.watch(authProvider.select((s) => s.user));

    return Container(
      height: _cardHeight + 24,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        itemCount: groups.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CreateStoryCard(
              avatarUrl: me?.avatarUrl,
              label: l10n.storiesCreate,
              onTap: () => context.push('/stories/create'),
            );
          }
          final group = groups[index - 1];
          final isMine = group.author.id == me?.id;
          return _StoryCard(
            group: group,
            isMine: isMine,
            label: isMine ? l10n.storiesYourStory : group.author.fullName,
            onTap: () => context.push(
              '/stories/view',
              extra: StoryViewerArgs(groupIndex: index - 1),
            ),
          );
        },
      ),
    );
  }
}

class _CreateStoryCard extends StatelessWidget {
  final String? avatarUrl;
  final String label;
  final VoidCallback onTap;

  const _CreateStoryCard({
    required this.avatarUrl,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasAvatar = avatarUrl != null && avatarUrl!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: StoriesRail._cardWidth,
        height: StoriesRail._cardHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasAvatar)
              CachedNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              )
            else
              Center(child: Icon(Icons.person, size: 44, color: scheme.primary)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xDD000000)],
                  stops: [0.45, 1],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: Icon(Icons.add, size: 18, color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  final StoryGroup group;
  final bool isMine;
  final String label;
  final VoidCallback onTap;

  const _StoryCard({
    required this.group,
    required this.isMine,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The newest story is what the card previews.
    final preview = group.stories.last;
    final ringActive = isMine || group.hasUnseen;
    final avatarUrl = group.author.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: StoriesRail._cardWidth,
        height: StoriesRail._cardHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _StoryPreview(story: preview),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Colors.transparent, Color(0xDD000000)],
                  stops: [0, 0.4, 1],
                ),
              ),
            ),
            PositionedDirectional(
              top: 8,
              start: 8,
              child: Container(
                width: 36,
                height: 36,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: ringActive
                      ? LinearGradient(
                          colors: [
                            scheme.primary,
                            Color.lerp(scheme.primary, const Color(0xFFEC4899), 0.6)!,
                          ],
                        )
                      : null,
                  color: ringActive ? null : Colors.white38,
                ),
                child: CircleAvatar(
                  backgroundColor: Colors.black,
                  backgroundImage:
                      hasAvatar ? CachedNetworkImageProvider(avatarUrl!) : null,
                  child: hasAvatar
                      ? null
                      : Icon(Icons.person, size: 16, color: scheme.primary),
                ),
              ),
            ),
            PositionedDirectional(
              start: 8,
              end: 8,
              bottom: 8,
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a story card shows behind its overlays: the photo, a video poster
/// frame, or the text story's colored background with a text snippet.
class _StoryPreview extends StatelessWidget {
  final StoryModel story;
  const _StoryPreview({required this.story});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(color: scheme.primary.withValues(alpha: 0.15));

    switch (story.contentType) {
      case StoryContentType.image:
        return story.mediaUrl == null
            ? placeholder
            : CachedNetworkImage(
                imageUrl: story.mediaUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              );
      case StoryContentType.video:
        final poster = story.mediaUrl == null ? '' : videoPosterUrl(story.mediaUrl!);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (poster.isNotEmpty)
              CachedNetworkImage(
                imageUrl: poster,
                fit: BoxFit.cover,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black87),
              )
            else
              const ColoredBox(color: Colors.black87),
            const Center(
              child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 34),
            ),
          ],
        );
      case StoryContentType.text:
        final bg = story.parsedBackground ?? scheme.primary;
        final fg = bg.computeLuminance() > 0.6 ? Colors.black : Colors.white;
        return Container(
          color: bg,
          padding: const EdgeInsets.all(10),
          alignment: Alignment.center,
          child: Text(
            story.textContent ?? '',
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        );
    }
  }
}
