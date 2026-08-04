import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/constants.dart';
import '../models/comment_model.dart';
import '../models/post_model.dart';

class PostService {
  final Dio _dio;

  PostService({Dio? dio}) : _dio = dio ?? ApiClient.instance.dio;

  /// Fetches the authenticated user's feed
  Future<List<PostModel>> getFeed({int skip = 0, int limit = 20}) async {
    try {
      final response = await _dio.get(
        ApiConfig.postsFeed,
        queryParameters: {'skip': skip, 'limit': limit},
      );

      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((json) => PostModel.fromJson(json as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Creates a new post
  Future<PostModel> createPost({
    String? content,
    PostType postType = PostType.text,
    String? mediaUrl,
    String? tags,
  }) async {
    try {
      final response = await _dio.post(
        ApiConfig.createPost,
        data: {
          if (content != null && content.isNotEmpty) 'content': content,
          'post_type': postType.value,
          if (mediaUrl != null && mediaUrl.isNotEmpty) 'media_url': mediaUrl,
          if (tags != null && tags.isNotEmpty) 'tags': tags,
        },
      );

      return PostModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Deletes a post owned by the user
  Future<void> deletePost(int postId) async {
    try {
      await _dio.delete(ApiConfig.deletePost(postId));
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Toggles like status for a post
  Future<bool> toggleLike(int postId) async {
    try {
      final response = await _dio.post(ApiConfig.toggleLike(postId));
      final action = response.data['action'] as String?;
      return action == 'liked';
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Adds a comment to a post
  Future<CommentModel> addComment(int postId, String content) async {
    try {
      final response = await _dio.post(
        ApiConfig.addComment(postId),
        data: {'content': content},
      );
      return CommentModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// Uploads an image file for a post and returns the media URL
  Future<String> uploadPostImage(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name.isNotEmpty ? file.name : 'upload.jpg',
        ),
      });

      final response = await _dio.post(
        ApiConfig.uploadPostImage,
        data: formData,
      );

      return response.data['url'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
