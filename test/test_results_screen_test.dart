import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/results_service.dart';
import 'package:enclavd/screens/test_results_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

class _FakeResults extends ResultsService {
  _FakeResults({this.results, this.error})
      : super(ApiClient(
            store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  final TestResults? results;
  final ApiException? error;

  @override
  Future<TestResults> fetchResults() async {
    if (error != null) throw error!;
    return results!;
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

const _sample = TestResults(
  personalityType: 'INTJ',
  color: 'gold',
  expiresOn: '2035-12-01 00:00:00',
  iePercentage: 88,
  snPercentage: 18,
  tfPercentage: 100,
  jpPercentage: 64,
  title: 'Strategic, Visionary',
  description: 'INTJs are known for their brilliant minds.',
  strengths: ['Highly analytical', 'Sees the big picture'],
  weaknesses: ['Can struggle with interpersonal relationships'],
);

void main() {
  testWidgets('loaded results render the badge, traits and strengths',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: TestResultsScreen(results: _FakeResults(results: _sample)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('INTJ'), findsOneWidget);
    expect(find.text('The Strategic, Visionary'), findsOneWidget);
    expect(find.text('Highly analytical'), findsOneWidget);
    expect(find.text('Can struggle with interpersonal relationships'),
        findsOneWidget);
    expect(find.text('Introversion - Extraversion'), findsOneWidget);
    // 88% introversion + 12% extraversion side labels (Text.rich spans).
    expect(find.textContaining('88%', findRichText: true), findsOneWidget);
    expect(find.textContaining('12%', findRichText: true), findsOneWidget);

    // The remaining trait bars are below the fold — scroll the list.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('Sensing - Intuition'), findsOneWidget);
    expect(find.text('Thinking - Feeling'), findsOneWidget);
    expect(find.text('Judging - Perceiving'), findsOneWidget);
  });

  testWidgets('404 shows the take-the-test empty state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: TestResultsScreen(
          results: _FakeResults(
              error: const ApiException('No test results yet', status: 404))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No test results yet'), findsOneWidget);
    expect(find.text('Take the test'), findsOneWidget);
    expect(find.text('INTJ'), findsNothing);
  });

  testWidgets('other errors show a retry state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: TestResultsScreen(
          results: _FakeResults(
              error: const ApiException('Network error'))),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Network error'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
