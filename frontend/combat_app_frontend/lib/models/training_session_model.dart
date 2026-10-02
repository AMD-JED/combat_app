/// Mirrors `app/schemas/training.py::TrainingSessionType` (backend v8).
enum TrainingSessionType {
  solo('solo'),
  classSession('class'),
  sparring('sparring'),
  conditioning('conditioning'),
  technique('technique'),
  other('other');

  final String value;
  const TrainingSessionType(this.value);

  static TrainingSessionType fromString(String raw) {
    return TrainingSessionType.values.firstWhere(
      (e) => e.value == raw,
      orElse: () => TrainingSessionType.other,
    );
  }
}

/// Mirrors `TrainingSessionSummary` (backend v8, `GET /training/sessions`).
/// Deliberately thin: this powers only the small "recent sessions" list on
/// the athlete's own profile, not a full training log/editor — the app has
/// no screen for creating or browsing training sessions yet.
class TrainingSessionModel {
  final int id;
  final TrainingSessionType sessionType;
  final int durationMinutes;

  /// 1 (lightest) to 5 (hardest). The backend leaves this unset on older or
  /// quickly-logged sessions, hence nullable.
  final int? intensity;
  final DateTime sessionDate;

  const TrainingSessionModel({
    required this.id,
    required this.sessionType,
    required this.durationMinutes,
    required this.intensity,
    required this.sessionDate,
  });

  factory TrainingSessionModel.fromJson(Map<String, dynamic> json) {
    return TrainingSessionModel(
      id: json['id'] as int,
      sessionType: TrainingSessionType.fromString(json['session_type'] as String),
      durationMinutes: (json['duration_minutes'] as num).toInt(),
      intensity: (json['intensity'] as num?)?.toInt(),
      sessionDate: DateTime.parse(json['session_date'] as String),
    );
  }
}
