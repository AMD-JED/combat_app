import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/story_model.dart';
import '../services/story_service.dart';
import '../services/upload_service.dart';
import 'auth_provider.dart';

class StoriesState {
  final List<StoryGroup> groups;
  final bool isLoading;
  final String? errorMessage;

  const StoriesState({
    this.groups = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  /// The group of the signed-in user, if they have an active story.
  StoryGroup? myGroup(int? myUserId) {
    for (final g in groups) {
      if (g.author.id == myUserId) return g;
    }
    return null;
  }

  /// Latest version of a story (likes/views change while the viewer is open).
  StoryModel? storyById(int storyId) {
    for (final group in groups) {
      for (final story in group.stories) {
        if (story.id == storyId) return story;
      }
    }
    return null;
  }

  StoriesState copyWith({
    List<StoryGroup>? groups,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return StoriesState(
      groups: groups ?? this.groups,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// The stories rail / viewer state. Stories are grouped per author
/// (`groupStories`) and every mutation (view, like, delete, publish) is
/// applied to the local copy as well, so the UI never waits for a refetch.
class StoriesNotifier extends StateNotifier<StoriesState> {
  StoriesNotifier(this._myUserId) : super(const StoriesState()) {
    // Same pattern as `feedProvider`: the first widget that watches the
    // provider (the rail on the feed screen) triggers the first load.
    if (_myUserId != null) Future.microtask(fetch);
  }

  final int? _myUserId;
  final StoryService _service = StoryService();
  final UploadService _uploads = UploadService();

  Future<void> fetch() async {
    final myId = _myUserId;
    if (myId == null) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final stories = await _service.getFeed();
      if (!mounted) return;
      state = state.copyWith(
        groups: groupStories(stories, myUserId: myId),
        isLoading: false,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Applies [transform] to one story in place. Group order is kept (it is
  /// only recomputed on a fetch), so the rail doesn't reshuffle while the
  /// viewer is open.
  void _updateStory(int storyId, StoryModel Function(StoryModel) transform) {
    final groups = state.groups.map((group) {
      if (!group.stories.any((s) => s.id == storyId)) return group;
      return StoryGroup(
        author: group.author,
        stories: group.stories.map((s) => s.id == storyId ? transform(s) : s).toList(),
      );
    }).toList();
    state = state.copyWith(groups: groups);
  }

  /// Marks a story seen locally and tells the backend (fire-and-forget: a
  /// failed call only means the author's "seen by" list misses this view).
  void markViewed(int storyId) {
    final story = state.storyById(storyId);
    if (story == null || story.viewedByMe || story.author.id == _myUserId) return;
    _updateStory(storyId, (s) => s.copyWith(viewedByMe: true));
    _service.markViewed(storyId).catchError((_) {});
  }

  /// Optimistic heart toggle, rolled back if the request fails.
  Future<void> toggleLike(int storyId) async {
    final before = state.storyById(storyId);
    if (before == null) return;
    _updateStory(storyId, (s) {
      final liked = !s.likedByMe;
      final count = s.likesCount + (liked ? 1 : -1);
      return s.copyWith(likedByMe: liked, likesCount: count < 0 ? 0 : count);
    });
    try {
      final result = await _service.toggleLike(storyId);
      if (!mounted) return;
      _updateStory(
        storyId,
        (s) => s.copyWith(likedByMe: result.liked, likesCount: result.likesCount),
      );
    } catch (_) {
      if (!mounted) return;
      _updateStory(
        storyId,
        (s) => s.copyWith(likedByMe: before.likedByMe, likesCount: before.likesCount),
      );
    }
  }

  /// Returns the id of the conversation the reply landed in, or null when it
  /// could not be sent.
  Future<int?> reply(int storyId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      return await _service.reply(storyId, trimmed);
    } catch (_) {
      return null;
    }
  }

  Future<List<StoryViewer>> loadViewers(int storyId) => _service.getViewers(storyId);

  Future<bool> delete(int storyId) async {
    try {
      await _service.delete(storyId);
      if (!mounted) return true;
      final groups = state.groups
          .map((g) => StoryGroup(
                author: g.author,
                stories: g.stories.where((s) => s.id != storyId).toList(),
              ))
          .where((g) => g.stories.isNotEmpty)
          .toList();
      state = state.copyWith(groups: groups);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Uploads the media (image/video) then creates the story; text stories
  /// skip the upload. Throws on failure so the create screen can show it.
  Future<void> publish({
    required StoryContentType contentType,
    XFile? file,
    String? text,
    String? backgroundColor,
    StoryVisibility visibility = StoryVisibility.public,
  }) async {
    String? mediaUrl;
    if (contentType != StoryContentType.text) {
      mediaUrl = await _uploads.uploadStoryMedia(
        file!,
        isVideo: contentType == StoryContentType.video,
      );
    }
    final trimmed = text?.trim();
    await _service.create(
      contentType: contentType,
      mediaUrl: mediaUrl,
      textContent: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      backgroundColor: backgroundColor,
      visibility: visibility,
    );
    await fetch();
  }
}

/// Rebuilt (empty state, new user id) whenever the signed-in account changes.
final storiesProvider = StateNotifierProvider<StoriesNotifier, StoriesState>((ref) {
  final userId = ref.watch(authProvider.select((s) => s.user?.id));
  return StoriesNotifier(userId);
});
