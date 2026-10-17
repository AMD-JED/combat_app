import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/constants.dart';
import '../core/multipart_helper.dart';

/// Talks to `app/api/v1/endpoints/uploads.py` (avatar only for v1).
class UploadService {
  final Dio _dio = ApiClient.instance.dio;

  /// POST /uploads/avatar (multipart) → { message, avatar_url }
  /// The backend auto-crops to the face (400×400) and converts to WebP,
  /// and also saves the URL onto the user's profile server-side — so no
  /// separate PATCH /users/me call is needed after this.
  Future<String> uploadAvatar(XFile file) async {
    try {
      final formData = FormData.fromMap({
        'file': await multipartFromXFile(file),
      });
      final response = await _dio.post(ApiConfig.uploadAvatar, data: formData);
      return response.data['avatar_url'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /uploads/message/image|video (multipart) → { url, ... }
  /// Uploads a chat attachment and returns the Cloudinary `url` to send as
  /// `media_url` (the backend only accepts https Cloudinary URLs there).
  Future<String> uploadMessageMedia(XFile file, {required bool isVideo}) async {
    try {
      final formData = FormData.fromMap({
        'file': await multipartFromXFile(file),
      });
      final response = await _dio.post(
        isVideo ? ApiConfig.uploadMessageVideo : ApiConfig.uploadMessageImage,
        data: formData,
      );
      return response.data['url'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /uploads/story/image|video (multipart) → { url, ... }
  Future<String> uploadStoryMedia(XFile file, {required bool isVideo}) async {
    try {
      final formData = FormData.fromMap({
        'file': await multipartFromXFile(file),
      });
      final response = await _dio.post(
        isVideo ? ApiConfig.uploadStoryVideo : ApiConfig.uploadStoryImage,
        data: formData,
      );
      return response.data['url'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /uploads/reel/video (multipart) → { url, thumbnail_url?, duration? }
  ///
  /// The endpoint waits on Cloudinary's upload before answering, so it gets
  /// the same long timeout as post videos instead of the shared 15 s default.
  Future<ReelUpload> uploadReelVideo(XFile file) async {
    try {
      final formData = FormData.fromMap({
        'file': await multipartFromXFile(file),
      });
      final response = await _dio.post(
        ApiConfig.uploadReelVideo,
        data: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 5),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      final data = response.data as Map<String, dynamic>;
      return ReelUpload(
        url: data['url'] as String,
        thumbnailUrl: data['thumbnail_url'] as String?,
        durationSeconds: (data['duration'] as num?)?.round(),
      );
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}

/// Result of [UploadService.uploadReelVideo]. `durationSeconds` is already an
/// int: Cloudinary reports a float, but `ReelCreate.duration_seconds` is an
/// integer field and rejects fractions.
class ReelUpload {
  final String url;
  final String? thumbnailUrl;
  final int? durationSeconds;

  const ReelUpload({required this.url, this.thumbnailUrl, this.durationSeconds});
}
