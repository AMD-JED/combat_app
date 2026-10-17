import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/comment_model.dart';
import '../models/reel_model.dart';
import '../services/reel_service.dart';
import '../services/upload_service.dart';
import '../services/user_service.dart';
import 'auth_provider.dart';

class ReelsState {
  final List<ReelModel> reels;

  /// Sport filter (a `sports.id`); null = "For you" (every sport).
  final int? sportId;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;

  const ReelsState({
    this.reels = const [],
    this.sportId,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.errorMessage,
  });

  ReelsState copyWith({
    List<ReelModel>? reels,
    int? sportId,
    bool clearSport = false,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ReelsState(
      reels: reels ?? this.reels,
      sportId: clearSport ? null : (sportId ?? this.sportId),
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// The Reels tab. Every mutation (like, follow, comment, delete) is applied
/// to the local list as well so the UI never waits for a refetch.
class ReelsNotifier extends StateNotifier<ReelsState> {
  ReelsNotifier(this._myUserId) : super(const ReelsState());

  static const int pageSize = 20;

  final int? _myUserId;
  final ReelService _service = ReelService();
  final UploadService _uploads = UploadService();
  final UserService _users = UserService();

  bool _started = false;
  int _requestToken = 0; // drops the answer of a superseded fetch
  final Set<int> _viewed = {};

  /// Called by the screen the first time the tab becomes visible, so a user
  /// who never opens Reels never pays for the request.
  void ensureLoaded() {
    if (_started || _myUserId == null) return;
    _started = true;
    fetch();
  }

  Future<void> fetch() async {
    if (_myUserId == null) return;
    _started = true;
    final token = ++_requestToken;
    state = state.copyWith(isLoading: true, isLoadingMore: false, clearError: true);
    try {
      final page = await _service.getFeed(sportId: state.sportId, limit: pageSize);
      if (!mounted || token != _requestToken) return;
      state = state.copyWith(
        reels: page,
        hasMore: page.length >= pageSize,
        isLoading: false,
      );
    } catch (e) {
      if (!mounted || token != _requestToken) return;
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> setSport(int? sportId) async {
    if (sportId == state.sportId) return;
    state = sportId == null
        ? state.copyWith(clearSport: true, reels: const [])
        : state.copyWith(sportId: sportId, reels: const []);
    await fetch();
  }

  Future<void> loadMore() async {
    if (_myUserId == null || state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final token = _requestToken;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _service.getFeed(
        sportId: state.sportId,
        skip: state.reels.length,
        limit: pageSize,
      );
      if (!mounted || token != _requestToken) return;
      final known = state.reels.map((r) => r.id).toSet();
      state = state.copyWith(
        reels: [...state.reels, ...page.where((r) => !known.contains(r.id))],
        hasMore: page.length >= pageSize,
        isLoadingMore: false,
      );
    } catch (_) {
      if (!mounted || token != _requestToken) return;
      // Keep what is already loaded; the next swipe near the end retries.
      state = state.copyWith(isLoadingMore: false);
    }
  }

  void _update(int reelId, ReelModel Function(ReelModel) transform) {
    state = state.copyWith(
      reels: state.reels.map((r) => r.id == reelId ? transform(r) : r).toList(),
    );
  }

  ReelModel? byId(int reelId) {
    for (final r in state.reels) {
      if (r.id == reelId) return r;
    }
    return null;
  }

  /// Counts one view per reel per session (fire-and-forget).
  void markViewed(int reelId) {
    if (!_viewed.add(reelId)) return;
    final reel = byId(reelId);
    if (reel == null || reel.author.id == _myUserId) return;
    _service.recordView(reelId).catchError((_) {});
  }

  /// Optimistic heart toggle, rolled back if the request fails.
  Future<void> toggleLike(int reelId) async {
    final before = byId(reelId);
    if (before == null) return;
    _update(reelId, (r) {
      final liked = !r.likedByMe;
      final count = r.likesCount + (liked ? 1 : -1);
      return r.copyWith(likedByMe: liked, likesCount: count < 0 ? 0 : count);
    });
    try {
      final liked = await _service.toggleLike(reelId);
      if (!mounted) return;
      // The server answered with the real state; fix the count if we guessed
      // the direction wrong (e.g. a double tap raced a like from another tab).
      final now = byId(reelId);
      if (now != null && now.likedByMe != liked) {
        _update(reelId, (r) {
          final count = r.likesCount + (liked ? 1 : -1);
          return r.copyWith(likedByMe: liked, likesCount: count < 0 ? 0 : count);
        });
      }
    } catch (_) {
      if (!mounted) return;
      _update(
        reelId,
        (r) => r.copyWith(likedByMe: before.likedByMe, likesCount: before.likesCount),
      );
    }
  }

  /// Follow / unfollow an author; every loaded reel of theirs is updated.
  /// The endpoint is a pure toggle, so the target state is the opposite of
  /// what the reel currently shows.
  Future<void> toggleFollow(int authorId) async {
    if (authorId == _myUserId) return;
    final ofAuthor = state.reels.where((r) => r.author.id == authorId);
    if (ofAuthor.isEmpty) return;
    final wasFollowing = ofAuthor.first.followingAuthor;
    _setFollowing(authorId, !wasFollowing);
    try {
      final action = await _users.toggleFollow(authorId);
      if (!mounted) return;
      _setFollowing(authorId, action == 'followed');
    } catch (_) {
      if (!mounted) return;
      _setFollowing(authorId, wasFollowing);
    }
  }

  void _setFollowing(int authorId, bool following) {
    state = state.copyWith(
      reels: state.reels
          .map((r) => r.author.id == authorId ? r.copyWith(followingAuthor: following) : r)
          .toList(),
    );
  }

  Future<bool> delete(int reelId) async {
    try {
      await _service.delete(reelId);
      if (!mounted) return true;
      state = state.copyWith(reels: state.reels.where((r) => r.id != reelId).toList());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<CommentModel>> loadComments(int reelId) => _service.getComments(reelId);

  /// Returns the new comment, or null when it could not be sent.
  Future<CommentModel?> addComment(int reelId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      final comment = await _service.addComment(reelId, trimmed);
      if (!mounted) return comment;
      _update(reelId, (r) => r.copyWith(commentsCount: r.commentsCount + 1));
      return comment;
    } catch (_) {
      return null;
    }
  }

  /// Uploads the video, creates the reel, then reloads the feed from the top
  /// with no sport filter so the person sees their new reel first. Throws on
  /// failure so the create screen can show it.
  Future<void> publish({
    required XFile file,
    String? caption,
    int? sportId,
  }) async {
    final upload = await _uploads.uploadReelVideo(file);
    final trimmed = caption?.trim();
    await _service.create(
      mediaUrl: upload.url,
      thumbnailUrl: upload.thumbnailUrl,
      caption: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      sportId: sportId,
      durationSeconds: upload.durationSeconds,
    );
    if (!mounted) return;
    state = state.copyWith(clearSport: true);
    await fetch();
  }
}

/// Rebuilt (empty state, new user id) whenever the signed-in account changes.
final reelsProvider = StateNotifierProvider<ReelsNotifier, ReelsState>((ref) {
  final userId = ref.watch(authProvider.select((s) => s.user?.id));
  return ReelsNotifier(userId);
});
