/// Mirrors `SportResponse` from `/api/v1/sports/` exactly
/// (id, slug, name, is_active — confirmed via openapi.json).
class SportModel {
  final int id;
  final String slug;
  final String name;
  final bool isActive;

  const SportModel({
    required this.id,
    required this.slug,
    required this.name,
    required this.isActive,
  });

  factory SportModel.fromJson(Map<String, dynamic> json) {
    return SportModel(
      id: json['id'] as int,
      slug: json['slug'] as String,
      name: json['name'] as String,
      isActive: json['is_active'] as bool,
    );
  }
}

/// Mirrors `UserSportProfileResponse`. `attributes` is a free-form map —
/// its actual required/allowed keys depend on `sport.slug` and are validated
/// server-side (`extra="forbid"` per-sport schema in `app/schemas/sport.py`,
/// not exposed as distinct components in openapi.json). Treat as opaque
/// until we have those per-sport schemas.
class UserSportProfileModel {
  final int id;
  final SportModel sport;
  final bool isPrimary;
  final Map<String, dynamic> attributes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const UserSportProfileModel({
    required this.id,
    required this.sport,
    required this.isPrimary,
    required this.attributes,
    required this.createdAt,
    this.updatedAt,
  });

  factory UserSportProfileModel.fromJson(Map<String, dynamic> json) {
    return UserSportProfileModel(
      id: json['id'] as int,
      sport: SportModel.fromJson(json['sport'] as Map<String, dynamic>),
      isPrimary: json['is_primary'] as bool,
      attributes: Map<String, dynamic>.from(json['attributes'] as Map? ?? {}),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }
}
