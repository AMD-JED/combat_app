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
}
