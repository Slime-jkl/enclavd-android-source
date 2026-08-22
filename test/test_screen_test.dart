import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/personality_test_service.dart';
import 'package:enclavd/screens/test_screen.dart';

/// PersonalityTestService that answers from memory — widget tests run in a
/// fake-async zone where real sockets never complete.
class _FakeTestService extends PersonalityTestService {
  _FakeTestService()
      : super(ApiClient(
          store: _NoopStore(),
          apiBaseUrl: 'https://example.com',
        ));

  bool alreadyTaken = false;
  int questionCount = 2;
  Map<int, String>? submitted;
  ApiException? submitError;

  @override
  Future<PersonalityTestInfo> fetchTest() async => PersonalityTestInfo(
        alreadyTaken: alreadyTaken,
        questions: [
          for (var i = 1; i <= questionCount; i++)
            PersonalityQuestion(id: i, question: 'Question text $i'),
        ],
      );

  @override
  Future<TestSubmissionResult> submit(Map<int, String> answers) async {
    if (submitError != null) throw submitError!;
    submitted = answers;
    return const TestSubmissionResult(
      personalityType: 'ISTJ',
      color: 'orange',
      expiresOn: '2036-08-22',
      iePercentage: 100,
      snPercentage: 100,
      tfPercentage: 100,
      jpPercentage: 100,
    );
  }
}

class _NoopStore implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

Widget _app(_FakeTestService service) => MaterialApp(
      home: TestScreen(
        test: service,
        resultsBuilder: (_) => const Scaffold(body: Text('RESULTS_VIEW')),
      ),
    );

void main() {
  testWidgets('intro → quiz → submit replaces with results', (tester) async {
    final service = _FakeTestService();
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    // Intro card (site test_page.php copy).
    expect(find.text('About this test'), findsOneWidget);
    expect(find.textContaining('40 questions'), findsOneWidget);

    // The redesigned intro is taller than the test viewport — scroll to
    // the action before tapping.
    await tester.scrollUntilVisible(find.text('Start Test'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Start Test'), findsOneWidget);

    await tester.tap(find.text('Start Test'));
    await tester.pumpAndSettle();

    // Question 1 of 2 — Next is disabled until an option is selected.
    expect(find.text('Question 1 of 2'), findsOneWidget);
    expect(find.text('Question text 1'), findsOneWidget);
    final nextBtn = find.widgetWithText(FilledButton, 'Next Question');
    expect(tester.widget<FilledButton>(nextBtn).onPressed, isNull);

    await tester.tap(find.text('Strongly Agree'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(nextBtn).onPressed, isNotNull);

    await tester.tap(nextBtn);
    await tester.pumpAndSettle();
    expect(find.text('Question 2 of 2'), findsOneWidget);
    expect(find.text('Question text 2'), findsOneWidget);

    await tester.tap(find.text('Neutral'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Test'));
    await tester.pumpAndSettle();

    // Submitted both answers; the quiz was replaced by the results view.
    expect(service.submitted, {1: 'strongly_agree', 2: 'neutral'});
    expect(find.text('RESULTS_VIEW'), findsOneWidget);
    expect(find.text('Question 1 of 2'), findsNothing);
  });

  testWidgets('already_taken jumps straight to results', (tester) async {
    final service = _FakeTestService()..alreadyTaken = true;
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();

    expect(find.text('RESULTS_VIEW'), findsOneWidget);
    expect(find.text('About this test'), findsNothing);
  });

  testWidgets('load failure shows retry', (tester) async {
    var fail = true;
    final stub = _FailingService(() => fail);
    await tester.pumpWidget(MaterialApp(
      home: TestScreen(
        test: stub,
        resultsBuilder: (_) => const Scaffold(body: Text('RESULTS_VIEW')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('About this test'), findsNothing);

    // Retry succeeds → intro appears.
    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('About this test'), findsOneWidget);
  });
}

class _FailingService extends PersonalityTestService {
  _FailingService(this._shouldFail)
      : super(ApiClient(
          store: _NoopStore(),
          apiBaseUrl: 'https://example.com',
        ));

  final bool Function() _shouldFail;

  @override
  Future<PersonalityTestInfo> fetchTest() async {
    if (_shouldFail()) {
      throw const ApiException('Network down');
    }
    return const PersonalityTestInfo(
      alreadyTaken: false,
      questions: [
        PersonalityQuestion(id: 1, question: 'Q1'),
        PersonalityQuestion(id: 2, question: 'Q2'),
      ],
    );
  }
}
