import '../../../l10n/app_localizations.dart';
import '../../../models/training_session_model.dart';
import '../../../models/user_model.dart';

/// Localized display label for a [SportType]. `.value` on the enum itself
/// is the raw English wire value the backend expects — never show it
/// directly; this is the translated label the UI shows instead.
String sportTypeLabel(AppLocalizations l10n, SportType? sport) {
  switch (sport) {
    case SportType.mma:
      return l10n.sportMma;
    case SportType.boxing:
      return l10n.sportBoxing;
    case SportType.bjj:
      return l10n.sportBjj;
    case SportType.muayThai:
      return l10n.sportMuayThai;
    case SportType.wrestling:
      return l10n.sportWrestling;
    case SportType.judo:
      return l10n.sportJudo;
    case SportType.karate:
      return l10n.sportKarate;
    case SportType.kickboxing:
      return l10n.sportKickboxing;
    case SportType.other:
      return l10n.sportOther;
    case null:
      return '—';
  }
}

/// Localized display label for a [WeightClass].
String weightClassLabel(AppLocalizations l10n, WeightClass? weight) {
  switch (weight) {
    case WeightClass.strawweight:
      return l10n.weightStrawweight;
    case WeightClass.flyweight:
      return l10n.weightFlyweight;
    case WeightClass.bantamweight:
      return l10n.weightBantamweight;
    case WeightClass.featherweight:
      return l10n.weightFeatherweight;
    case WeightClass.lightweight:
      return l10n.weightLightweight;
    case WeightClass.welterweight:
      return l10n.weightWelterweight;
    case WeightClass.middleweight:
      return l10n.weightMiddleweight;
    case WeightClass.lightHeavyweight:
      return l10n.weightLightHeavyweight;
    case WeightClass.heavyweight:
      return l10n.weightHeavyweight;
    case null:
      return '—';
  }
}

/// Localized display label for a [TrainingSessionType] — stands in for the
/// free-text "title" the prototype's mock sessions have; the backend only
/// stores a fixed session-type enum, not a custom title.
String trainingSessionTypeLabel(AppLocalizations l10n, TrainingSessionType type) {
  switch (type) {
    case TrainingSessionType.solo:
      return l10n.trainingSolo;
    case TrainingSessionType.classSession:
      return l10n.trainingClass;
    case TrainingSessionType.sparring:
      return l10n.trainingSparring;
    case TrainingSessionType.conditioning:
      return l10n.trainingConditioning;
    case TrainingSessionType.technique:
      return l10n.trainingTechnique;
    case TrainingSessionType.other:
      return l10n.trainingOther;
  }
}
