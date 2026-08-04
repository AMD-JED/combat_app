/// Mirrors `app/models/user.py::SportType` — values must match the backend
/// enum's *string values* exactly, since that's what's sent over JSON.
enum SportType {
  mma('MMA'),
  boxing('Boxing'),
  bjj('BJJ'),
  muayThai('Muay Thai'),
  wrestling('Wrestling'),
  judo('Judo'),
  karate('Karate'),
  kickboxing('Kickboxing'),
  other('Other');

  final String value;
  const SportType(this.value);

  static SportType? fromString(String? raw) {
    if (raw == null) return null;
    return SportType.values.where((e) => e.value == raw).firstOrNull;
  }
}

/// Mirrors `app/models/user.py::WeightClass`.
enum WeightClass {
  strawweight('Strawweight'),
  flyweight('Flyweight'),
  bantamweight('Bantamweight'),
  featherweight('Featherweight'),
  lightweight('Lightweight'),
  welterweight('Welterweight'),
  middleweight('Middleweight'),
  lightHeavyweight('Light Heavyweight'),
  heavyweight('Heavyweight');

  final String value;
  const WeightClass(this.value);

  static WeightClass? fromString(String? raw) {
    if (raw == null) return null;
    return WeightClass.values.where((e) => e.value == raw).firstOrNull;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Combines fields from both `UserPublicResponse` and `UserPrivateResponse`
/// (schemas/user.py). Private-only fields (email, is_active, is_verified,
/// google_id) are nullable since they're absent when viewing someone else's
/// public profile (e.g. via GET /users/{username}).
class UserModel {
  final int id;
  final String username;
  final String fullName;
  final SportType? sportType;
  final WeightClass? weightClass;
  final String? beltRank;
  final String? gymAffiliation;
  final String? bio;
  final String? avatarUrl;
  final String? location;
  final int wins;
  final int losses;
  final int draws;
  final bool isCoach;
  final DateTime createdAt;

  // Private-only (present only on GET /auth/me — i.e. the logged-in user)
  final String? email;
  final bool? isActive;
  final bool? isVerified;

  const UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    this.sportType,
    this.weightClass,
    this.beltRank,
    this.gymAffiliation,
    this.bio,
    this.avatarUrl,
    this.location,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.isCoach,
    required this.createdAt,
    this.email,
    this.isActive,
    this.isVerified,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      username: json['username'] as String,
      fullName: json['full_name'] as String,
      sportType: SportType.fromString(json['sport_type'] as String?),
      weightClass: WeightClass.fromString(json['weight_class'] as String?),
      beltRank: json['belt_rank'] as String?,
      gymAffiliation: json['gym_affiliation'] as String?,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      location: json['location'] as String?,
      wins: (json['wins'] as num?)?.toInt() ?? 0,
      losses: (json['losses'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as num?)?.toInt() ?? 0,
      isCoach: json['is_coach'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      email: json['email'] as String?,
      isActive: json['is_active'] as bool?,
      isVerified: json['is_verified'] as bool?,
    );
  }

  String get record => '$wins-$losses-$draws';

  UserModel copyWith({
    String? fullName,
    SportType? sportType,
    WeightClass? weightClass,
    String? beltRank,
    String? gymAffiliation,
    String? bio,
    String? avatarUrl,
    String? location,
  }) {
    return UserModel(
      id: id,
      username: username,
      fullName: fullName ?? this.fullName,
      sportType: sportType ?? this.sportType,
      weightClass: weightClass ?? this.weightClass,
      beltRank: beltRank ?? this.beltRank,
      gymAffiliation: gymAffiliation ?? this.gymAffiliation,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      location: location ?? this.location,
      wins: wins,
      losses: losses,
      draws: draws,
      isCoach: isCoach,
      createdAt: createdAt,
      email: email,
      isActive: isActive,
      isVerified: isVerified,
    );
  }
}
