const kNoteDisplayStyleOptions = ['auto', 'sharp', 'flat'];
const kThemeModeOptions = ['system', 'light', 'dark'];
const kRetentionOptions = [0.8, 0.85, 0.9, 0.95];
const kDeckHardnessOptions = ['strict', 'medium', 'wide'];
const kDeckDrillCountOptions = [5, 10, 15, 20, 30];
const kAnswerInputModeOptions = ['multipleChoice', 'keyboard', 'none'];

const kNewCardsPerDayOptions = [3, 5, 10, 15, 20, 25, 30, 40, 50];
const kReviewCardsPerDayOptions = [50, 100, 150, 200, 300, 500, 9999];
const kLearnAheadMinutesOptions = [0, 5, 10, 15, 20, 30, 60];
final kDayRolloverHourOptions = List<int>.unmodifiable(
  List<int>.generate(24, (i) => i),
);
const kLearningStepsPresets = ['1,10', '1,5,10', '10', '15'];
const kRelearningStepsPresets = ['10', '1,10', '20', '30'];
const kGraduatingIntervalOptions = [1, 2, 3, 4, 7, 10];
const kEasyIntervalOptions = [2, 3, 4, 5, 7, 10, 14];
const kDrillTimeLimitSecondsOptions = [60, 90, 120, 180, 300];
