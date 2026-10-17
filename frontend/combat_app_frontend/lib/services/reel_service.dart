import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/constants.dart';
import '../models/comment_model.dart';
import '../models/reel_model.dart';

/// Talks to `app/api/v1/endpoints/reels.py`.
class ReelService {
  final Dio _dio = ApiClient.instance.dio;

  /// GET /reels/feed?sport_id=&skip=&limit= — newest first, optionally one sport.
  Future<List<ReelModel>> getFeed({int? sportId, int skip = 0, int limit = 20}) async {
    try {
      final response = await _dio.get(
        ApiConfig.reelsFeed,
        queryParameters: {
          if (sportId != null) 'sport_id': sportId,
          'skip': skip,
          'limit': limit,
        },
      );
      return (response.data as List)
          .map((e) => ReelModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /reels/ — `mediaUrl` comes from `UploadService.uploadReelVideo`.
  Future<ReelModel> create({
    required String mediaUrl,
    String? thumbnailUrl,
    String? caption,
    int? sportId,
    int? durationSeconds,
  }) async {
    try {
      final response = await _dio.post(
        ApiConfig.reels,
        data: {
          'media_url': mediaUrl,
          'thumbnail_url': thumbnailUrl,
          'caption': caption,
          'sport_id': sportId,
          'duration_seconds': durationSeconds,
        },
      );
      return ReelModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET /reels/{id} — the backend counts this as a view.
  Future<void> recordView(int reelId) async {
    try {
      await _dio.get(ApiConfig.reelById(reelId));
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /reels/{id}/like → { action: "liked"|"unliked" }. A pure toggle.
  Future<bool> toggleLike(int reelId) async {
    try {
      final response = await _dio.post(ApiConfig.reelLike(reelId));
      return response.data['action'] == 'liked';
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// DELETE /reels/{id} — author only.
  Future<void> delete(int reelId) async {
    try {
      await _dio.delete(ApiConfig.reelById(reelId));
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET /reels/{id}/comments — oldest first.
  Future<List<CommentModel>> getComments(int reelId) async {
    try {
      final response = await _dio.get(
        ApiConfig.reelComments(reelId),
        queryParameters: {'limit': 100},
      );
      return (response.data as List)
          .map((e) => CommentModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /reels/{id}/comments
  Future<CommentModel> addComment(int reelId, String content) async {
    try {
      final response = await _dio.post(
        ApiConfig.reelComments(reelId),
        data: {'content': content},
      );
      return CommentModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
