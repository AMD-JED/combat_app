import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/constants.dart';
import '../models/training_session_model.dart';

/// Talks to `app/api/v1/endpoints/training.py`. Read-only for now — just
/// enough to show recent sessions on the athlete's own profile. Creating or
/// browsing the full training log is a separate feature, not built yet.
class TrainingService {
  final Dio _dio = ApiClient.instance.dio;

  /// GET /training/sessions?limit=... → List<TrainingSessionSummary>
  /// Always the CURRENT user's own sessions — the backend has no way to
  /// fetch another user's training history (by design: it's private).
  Future<List<TrainingSessionModel>> getMySessions({int limit = 3}) async {
    try {
      final response = await _dio.get(
        ApiConfig.trainingSessions,
        queryParameters: {'limit': limit},
      );
      return (response.data as List)
          .map((e) => TrainingSessionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
