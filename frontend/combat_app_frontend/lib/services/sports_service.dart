import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/constants.dart';
import '../models/sport_model.dart';

/// Talks to `app/api/v1/endpoints/sports.py`.
class SportsService {
  final Dio _dio = ApiClient.instance.dio;

  /// GET /sports/ — public, no auth required.
  Future<List<SportModel>> listSports() async {
    try {
      final response = await _dio.get(ApiConfig.sportsList);
      return (response.data as List)
          .map((e) => SportModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET /sports/me/profiles — requires auth.
  Future<List<UserSportProfileModel>> getMyProfiles() async {
    try {
      final response = await _dio.get(ApiConfig.mySportProfiles);
      return (response.data as List)
          .map((e) => UserSportProfileModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// POST /sports/me/profiles
  /// NOTE: `attributes` shape is validated per `sportSlug` on the backend
  /// (`extra="forbid"`) but isn't exposed in openapi.json as distinct
  /// schemas — sending `{}` here until the actual per-sport required fields
  /// are confirmed. If the backend rejects an empty map for a given sport,
  /// surface that error to the user rather than guessing field names.
  Future<UserSportProfileModel> addSportProfile({
    required String sportSlug,
    bool isPrimary = false,
    Map<String, dynamic> attributes = const {},
  }) async {
    try {
      final response = await _dio.post(ApiConfig.mySportProfiles, data: {
        'sport_slug': sportSlug,
        'is_primary': isPrimary,
        'attributes': attributes,
      });
      return UserSportProfileModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// PATCH /sports/me/profiles/{profile_id}
  Future<UserSportProfileModel> updateSportProfile({
    required int profileId,
    bool? isPrimary,
    Map<String, dynamic>? attributes,
  }) async {
    try {
      final response = await _dio.patch(
        ApiConfig.sportProfile(profileId),
        data: {
          if (isPrimary != null) 'is_primary': isPrimary,
          if (attributes != null) 'attributes': attributes,
        },
      );
      return UserSportProfileModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// DELETE /sports/me/profiles/{profile_id}
  Future<void> deleteSportProfile(int profileId) async {
    try {
      await _dio.delete(ApiConfig.sportProfile(profileId));
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
