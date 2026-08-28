import 'api_client.dart';

/// One question of the personality assessment (port of test_page.php's
/// list, ids 1..40 from psy_test_questions).
class PersonalityQuestion {
  const PersonalityQuestion({required this.id, required this.question});

  final int id;
  final String question;

  factory PersonalityQuestion.fromJson(Map<String, dynamic> json) =>
      PersonalityQuestion(
        id: (json['id'] as num?)?.toInt() ?? 0,
        question: json['question'] as String? ?? '',
      );
}

/// The questions + whether the viewer can still take the test
/// (already_taken mirrors test_page.php's redirect to /results when a
/// valid test row exists).
class PersonalityTestInfo {
  const PersonalityTestInfo({
    required this.alreadyTaken,
    required this.questions,
  });

  final bool alreadyTaken;
  final List<PersonalityQuestion> questions;
}

/// The scored result of a submission. The server runs the site's OWN
/// scoring engine (questions_logic.php, incl. the random tie-break), so
/// the app's result always matches a browser-run test on the same answers.
class TestSubmissionResult {
  const TestSubmissionResult({
    required this.personalityType,
    required this.color,
    required this.expiresOn,
    required this.iePercentage,
    required this.snPercentage,
    required this.tfPercentage,
    required this.jpPercentage,
  });

  final String personalityType;
  final String color; // orange / gold / blue / green
  final String expiresOn; // DB UTC wall-clock (date part meaningful)
  final int iePercentage; // % Introversion; 100 - ie = % Extraversion
  final int snPercentage; // % Sensing; 100 - sn = % Intuition
  final int tfPercentage; // % Thinking; 100 - tf = % Feeling
  final int jpPercentage; // % Judging; 100 - jp = % Perceiving

  factory TestSubmissionResult.fromJson(Map<String, dynamic> json) {
    final traits = json['traits'] as Map<String, dynamic>? ?? const {};
    return TestSubmissionResult(
      personalityType: json['personality_type'] as String? ?? '',
      color: json['color'] as String? ?? '',
      expiresOn: json['expires_on'] as String? ?? '',
      iePercentage: (traits['ie_percentage'] as num?)?.toInt() ?? 50,
      snPercentage: (traits['sn_percentage'] as num?)?.toInt() ?? 50,
      tfPercentage: (traits['tf_percentage'] as num?)?.toInt() ?? 50,
      jpPercentage: (traits['jp_percentage'] as num?)?.toInt() ?? 50,
    );
  }
}

/// The site's 40-question assessment over api/v1. GET -> {already_taken,
/// questions:[{id, question}]} (40 rows, ids 1..40); POST (JSON + CSRF)
/// {answers:{'question_1':'strongly_agree', ...}} - all 40 required,
/// values strongly_agree|agree|neutral|disagree|strongly_disagree ->
/// {personality_type, color, expires_on, traits}. 409
/// {error:'Test already completed'} on retake (site rule).
class PersonalityTestService {
  PersonalityTestService(this._api);

  final ApiClient _api;

  Future<PersonalityTestInfo> fetchTest() async {
    final json = await _api.getJson('/api/v1/personality_test');
    final rawQuestions = json['questions'];
    if (rawQuestions is! List) {
      throw const ApiException('Invalid test response');
    }
    return PersonalityTestInfo(
      alreadyTaken: json['already_taken'] as bool? ?? false,
      questions: [
        for (final q in rawQuestions)
          if (q is Map<String, dynamic>) PersonalityQuestion.fromJson(q),
      ],
    );
  }

  /// Scores + persists the answers server-side and returns the result;
  /// throws ApiException(409) when a valid test already exists.
  Future<TestSubmissionResult> submit(Map<int, String> answers) async {
    final json = await _api.postJson('/api/v1/personality_test', {
      'answers': {
        for (final e in answers.entries) 'question_${e.key}': e.value,
      },
    });
    return TestSubmissionResult.fromJson(json);
  }
}
