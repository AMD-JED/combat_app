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
    String? tags,
  }) async {
    state = state.copyWith(isPosting: true, clearError: true);
    try {
      String? mediaUrl;
      if (imageFile != null) {
        mediaUrl = await _postService.uploadPostImage(imageFile);
      }

      final newPost = await _postService.createPost(
        content: content,
        postType: imageFile != null ? PostType.image : postType,
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

  Future<void> toggleLike(int postId) async {
    final index = state.posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;

    final post = state.posts[index];
    final newLikedState = !post.isLikedByMe;
    final newLikesCount = newLikedState ? post.likesCount + 1 : (post.likesCount - 1).clamp(0, 999999);

    // Optimistic update
    final updatedPost = post.copyWith(
      isLikedByMe: newLikedState,
      likesCount: newLikesCount,
    );

    final updatedPosts = List<PostModel>.from(state.posts);
    updatedPosts[index] = updatedPost;
    state = state.copyWith(posts: updatedPosts);

    try {
      await _postService.toggleLike(postId);
    } catch (_) {
      // Rollback on error
      updatedPosts[index] = post;
      state = state.copyWith(posts: updatedPosts);
    }
  }

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
