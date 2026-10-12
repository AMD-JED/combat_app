import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/constants.dart';
import '../models/story_model.dart';

/// Talks to `app/api/v1/endpoints/stories.py`.
class StoryService {
  final Dio _dio = ApiClient.instance.dio;

  /// GET /stories/feed — active stories from me + the people I follow.
  Future<List<StoryModel>> getFeed() async {
    try {
      final response = await _dio.get(
        ApiConfig.storiesFeed,
        queryParameters: {'limit': 100},
      );
      return (response.data as List)
          .map((e) => StoryModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /stories/ — for image/video, [textContent] is the caption.
  Future<StoryModel> create({
    required StoryContentType contentType,
    String? mediaUrl,
    String? textContent,
    String? backgroundColor,
    StoryVisibility visibility = StoryVisibility.public,
  }) async {
    try {
      final response = await _dio.post(
        ApiConfig.stories,
        data: {
          'content_type': contentType.value,
          'media_url': mediaUrl,
          'text_content': textContent,
          'background_color': backgroundColor,
          'visibility': visibility.value,
        },
      );
      return StoryModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET /stories/{id} — the backend records the view as a side effect (for
  /// anyone but the author).
  Future<void> markViewed(int storyId) async {
    try {
      await _dio.get(ApiConfig.storyById(storyId));
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /stories/{id}/like → { liked, likes_count }
  Future<({bool liked, int likesCount})> toggleLike(int storyId) async {
    try {
      final response = await _dio.post(ApiConfig.storyLike(storyId));
      final data = response.data as Map<String, dynamic>;
      return (
        liked: data['liked'] as bool,
        likesCount: (data['likes_count'] as num).toInt(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /stories/{id}/reply — sends a DM to the author and returns the id
  /// of the conversation it landed in (so the UI can offer "Open chat").
  Future<int> reply(int storyId, String content) async {
    try {
      final response = await _dio.post(
        ApiConfig.storyReply(storyId),
        data: {'content': content},
      );
      return response.data['conversation_id'] as int;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET /stories/{id}/views — author only.
  Future<List<StoryViewer>> getViewers(int storyId) async {
    try {
      final response = await _dio.get(ApiConfig.storyViews(storyId));
      return (response.data as List)
          .map((e) => StoryViewer.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// DELETE /stories/{id}
  Future<void> delete(int storyId) async {
    try {
      await _dio.delete(ApiConfig.storyById(storyId));
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
