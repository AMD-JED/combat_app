import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../models/comment_model.dart';
import '../models/post_model.dart';
import '../services/post_service.dart';

class FeedState {
  final List<PostModel> posts;
  final bool isLoading;
  final bool isPosting;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;

  const FeedState({
    this.posts = const [],
    this.isLoading = false,
    this.isPosting = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.errorMessage,
  });

  FeedState copyWith({
    List<PostModel>? posts,
    bool? isLoading,
    bool? isPosting,
    bool? isLoadingMore,
    bool? hasMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      isLoading: isLoading ?? this.isLoading,
      isPosting: isPosting ?? this.isPosting,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class FeedNotifier extends StateNotifier<FeedState> {
  FeedNotifier() : super(const FeedState()) {
    fetchFeed();
  }

  final PostService _postService = PostService();

  static const int _pageSize = 20;

  Future<void> fetchFeed() async {
    state = state.copyWith(isLoading: true, clearError: true, hasMore: true);
    try {
      final posts = await _postService.getFeed(skip: 0, limit: _pageSize);
      state = state.copyWith(
        posts: posts,
        isLoading: false,
        hasMore: posts.length == _pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// تُحمِّل المنشورات التالية عند الوصول لنهاية الـ Feed.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final newPosts = await _postService.getFeed(
        skip: state.posts.length,
        limit: _pageSize,
      );
      state = state.copyWith(
        posts: [...state.posts, ...newPosts],
        hasMore: newPosts.length == _pageSize,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, errorMessage: e.toString());
    }
  }

  Future<bool> createPost({
    String? content,
    PostType postType = PostType.text,
    XFile? imageFile,
    XFile? videoFile,
    String? tags,
  }) async {
    state = state.copyWith(isPosting: true, clearError: true);
    try {
      String? mediaUrl;
      PostType resolvedType = postType;
      if (videoFile != null) {
        mediaUrl = await _postService.uploadPostVideo(videoFile);
        resolvedType = PostType.video;
      } else if (imageFile != null) {
        mediaUrl = await _postService.uploadPostImage(imageFile);
        resolvedType = PostType.image;
      }

      final newPost = await _postService.createPost(
        content: content,
        postType: resolvedType,
        mediaUrl: mediaUrl,
        tags: tags,
      );

      state = state.copyWith(
        posts: [newPost, ...state.posts],
        isPosting: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isPosting: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Applies [reaction] to a post the way the backend does
  /// (`POST /posts/{id}/react`): no previous reaction -> add it; the same
  /// type again -> remove it (toggle off); a different type -> switch.
  /// The UI updates optimistically and rolls back if the request fails.
  Future<void> react(int postId, ReactionType reaction) async {
    final index = state.posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final post = state.posts[index];
    final previous = post.userReaction;

    final counts = Map<ReactionType, int>.from(post.reactionCounts);
    var total = post.likesCount;
    ReactionType? next;

    if (previous == reaction) {
      // Toggle off.
      counts[reaction] = _decrement(counts[reaction] ?? 0);
      total = _decrement(total);
      next = null;
    } else {
      if (previous != null) {
        // Switching type: the total stays the same.
        counts[previous] = _decrement(counts[previous] ?? 0);
      } else {
        total += 1;
      }
      counts[reaction] = (counts[reaction] ?? 0) + 1;
      next = reaction;
    }

    _replacePost(
      post.copyWith(
        reactionCounts: counts,
        likesCount: total,
        userReaction: next,
        clearUserReaction: next == null,
        isLikedByMe: next != null,
      ),
    );

    try {
      await _postService.reactToPost(postId, reaction);
    } catch (_) {
      // Rollback on error.
      _replacePost(post);
    }
  }

  int _decrement(int value) => value > 0 ? value - 1 : 0;

  void _replacePost(PostModel updated) {
    final index = state.posts.indexWhere((p) => p.id == updated.id);
    if (index == -1) return;
    final posts = List<PostModel>.from(state.posts);
    posts[index] = updated;
    state = state.copyWith(posts: posts);
  }

  /// Comments of a post, newest first. Errors are rethrown so the comments
  /// drawer can show its own retry state.
  Future<List<CommentModel>> fetchComments(int postId) => _postService.getComments(postId);

  Future<CommentModel?> addComment(int postId, String content) async {
    try {
      final comment = await _postService.addComment(postId, content);

      // Increment comments count on post
      final index = state.posts.indexWhere((p) => p.id == postId);
      if (index != -1) {
        final post = state.posts[index];
        final updatedPost = post.copyWith(commentsCount: post.commentsCount + 1);
        final updatedPosts = List<PostModel>.from(state.posts);
        updatedPosts[index] = updatedPost;
        state = state.copyWith(posts: updatedPosts);
      }

      return comment;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return null;
    }
  }

  Future<bool> deletePost(int postId) async {
    try {
      await _postService.deletePost(postId);
      state = state.copyWith(
        posts: state.posts.where((p) => p.id != postId).toList(),
      );
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }
}

final feedProvider = StateNotifierProvider<FeedNotifier, FeedState>((ref) {
  return FeedNotifier();
});
