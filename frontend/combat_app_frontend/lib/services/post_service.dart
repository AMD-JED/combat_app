import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/constants.dart';
import '../core/multipart_helper.dart';
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
      final formData = FormData.fromMap({
        'file': await multipartFromXFile(file),
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

  /// Uploads a video file for a post and returns the media URL.
  /// The backend also returns a `thumbnail_url` (Cloudinary auto-generates
  /// one at the 1s mark), but the `posts` table only has one `media_url`
  /// column today, so there's nowhere to persist it yet — the feed shows a
  /// generic video placeholder until that's added.
  ///
  /// Uses a much longer timeout than the shared 15s default: the endpoint
  /// waits on Cloudinary's transcode before responding, and a 200MB video
  /// (the backend's own limit) can easily take longer than that on an
  /// ordinary connection.
  Future<String> uploadPostVideo(XFile file) async {
    try {
      final formData = FormData.fromMap({
        'file': await multipartFromXFile(file),
      });

      final response = await _dio.post(
        ApiConfig.uploadPostVideo,
        data: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      return response.data['url'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
