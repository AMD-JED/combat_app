import 'package:dio/dio.dart';

/// Normalizes backend error responses (FastAPI returns `{"detail": "..."}`
/// or, for validation errors, `{"detail": [{"msg": "...", "loc": [...]}]}`).
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  factory ApiException.fromDioError(DioException error) {
    final response = error.response;
    if (response == null) {
      return ApiException('تعذّر الاتصال بالخادم. تأكد من تشغيل الـ Backend ومن صحة الـ Base URL.');
    }

    final data = response.data;
    String message = 'حدث خطأ غير متوقع (${response.statusCode})';

    if (data is Map && data['detail'] != null) {
      final detail = data['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        // Pydantic validation error format
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          message = first['msg'].toString();
        }
      }
    }

    return ApiException(message, statusCode: response.statusCode);
  }

  @override
  String toString() => message;
}
