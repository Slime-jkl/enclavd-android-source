import 'api_client.dart';

/// The viewer's latest personality test results
/// (GET /api/v1/results - port of results.php). A 404 (ApiException
/// status 404) means no valid test - the site redirects to /test_page in
/// that case.
class TestResults {
  const TestResults({
    required this.personalityType,
    required this.color,
    required this.expiresOn,
    required this.iePercentage,
    required this.snPercentage,
    required this.tfPercentage,
    required this.jpPercentage,
    required this.title,
    required this.description,
    required this.strengths,
    required this.weaknesses,
  });

  final String personalityType;
  final String color; // orange / gold / blue / green
  final String expiresOn; // DB UTC wall-clock
  final int iePercentage; // % Introversion; 100 - ie = % Extraversion
  final int snPercentage; // % Sensing; 100 - sn = % Intuition
  final int tfPercentage; // % Thinking; 100 - tf = % Feeling
  final int jpPercentage; // % Judging; 100 - jp = % Perceiving
  final String title; // core traits ("Strategic, Visionary, ...")
  final String description;
  final List<String> strengths;
  final List<String> weaknesses;

  factory TestResults.fromJson(Map<String, dynamic> json) {
    final traits = json['traits'] as Map<String, dynamic>? ?? const {};
    final info = json['info'] as Map<String, dynamic>? ?? const {};
    return TestResults(
      personalityType: json['personality_type'] as String? ?? '',
      color: json['color'] as String? ?? '',
      expiresOn: json['expires_on'] as String? ?? '',
      iePercentage: (traits['ie_percentage'] as num?)?.toInt() ?? 50,
      snPercentage: (traits['sn_percentage'] as num?)?.toInt() ?? 50,
      tfPercentage: (traits['tf_percentage'] as num?)?.toInt() ?? 50,
      jpPercentage: (traits['jp_percentage'] as num?)?.toInt() ?? 50,
      title: info['title'] as String? ?? '',
      description: info['description'] as String? ?? '',
      strengths: _stringList(info['strengths']),
      weaknesses: _stringList(info['weaknesses']),
    );
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<String>().toList();
  }
}

/// ResultsService - the personality test results over api/v1.
class ResultsService {
  ResultsService(this._api);

  final ApiClient _api;

  /// The viewer's latest valid test. Throws ApiException with status 404
  /// when there is no valid test yet (the caller shows the take-test
  /// empty state, mirroring the site's redirect to /test_page).
  Future<TestResults> fetchResults() async {
    final json = await _api.getJson('/api/v1/results');
    final raw = json['results'];
    if (raw is! Map<String, dynamic>) {
      throw const ApiException('Invalid results response');
    }
    return TestResults.fromJson(raw);
  }
}
