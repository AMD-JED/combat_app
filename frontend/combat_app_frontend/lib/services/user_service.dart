import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/constants.dart';
import '../models/user_model.dart';

/// Talks to `app/api/v1/endpoints/users.py`.
class UserService {
  final Dio _dio = ApiClient.instance.dio;

  /// GET /users/{username} → UserPublicResponse (works for any user, no auth required)
  Future<UserModel> getProfile(String username) async {
    try {
      final response = await _dio.get(ApiConfig.userProfile(username));
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// PATCH /users/me → UserPublicResponse
  /// Only send fields that changed — the backend uses
  /// `payload.model_dump(exclude_unset=True)`, and here we build the map
  /// manually so unchanged fields are simply omitted.
  Future<UserModel> updateProfile({
    String? fullName,
    SportType? sportType,
    WeightClass? weightClass,
    String? beltRank,
    String? gymAffiliation,
    String? coachName,
    String? bio,
    String? location,
    bool? isCoach,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (sportType != null) body['sport_type'] = sportType.value;
    if (weightClass != null) body['weight_class'] = weightClass.value;
    if (beltRank != null) body['belt_rank'] = beltRank;
    if (gymAffiliation != null) body['gym_affiliation'] = gymAffiliation;
    if (coachName != null) body['coach_name'] = coachName;
    if (bio != null) body['bio'] = bio;
    if (location != null) body['location'] = location;
    if (isCoach != null) body['is_coach'] = isCoach;

    try {
      final response = await _dio.patch(ApiConfig.updateMe, data: body);
      return UserModel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }

  /// GET /users/search?q=... → List<UserPublicResponse>
  /// Backend requires `q` to be at least 2 characters (`Query(..., min_length=2)`).
  Future<List<UserModel>> search(String query, {int skip = 0, int limit = 20}) async {
    try {
      final response = await _dio.get(ApiConfig.usersSearch, queryParameters: {
        'q': query,
        'skip': skip,
        'limit': limit,
      });
      return (response.data as List)
          .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDioError(e);
    }
  }
}
