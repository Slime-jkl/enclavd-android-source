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
  tfPercentage: 62,
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

  testWidgets('trait bars use the website colors for all 8 traits',
      (tester) async {
    // Regression: bars once rendered all gray (track showing through).
    // results.php: I/E blue+red, S/N green+purple, T/F yellow+pink,
    // J/P orange+indigo.
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: TestResultsScreen(results: _FakeResults(results: _sample)),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    Set<Color> barColors() => tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .map((b) => b.color)
        .toSet();

    expect(barColors().contains(const Color(0xFF3B82F6)), isTrue); // blue
    expect(barColors().contains(const Color(0xFFEF4444)), isTrue); // red

    // Each colored segment must actually PAINT, i.e. have non-zero size.
    // Real regression: the empty segment ColoredBoxes collapsed to 0px
    // height under the Row's loose cross-axis constraints (only the
    // gray track painted), so the bars looked all gray.
    void expectPaintable(Color color) {
      final f = find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == color);
      expect(f, findsWidgets, reason: 'no segment found for $color');
      for (final box in tester.renderObjectList<RenderBox>(f)) {
        expect(box.size.height, 8.0,
            reason: 'segment $color collapsed to height ${box.size.height}');
        expect(box.size.width, greaterThan(0),
            reason: 'segment $color has zero width');
      }
    }

    expectPaintable(const Color(0xFF3B82F6));
    expectPaintable(const Color(0xFFEF4444));

    // Segments are proportional to the percentages: 88% blue / 12% red.
    double segWidth(Color c) => tester
        .renderObject<RenderBox>(find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color == c))
        .size
        .width;
    final blueW = segWidth(const Color(0xFF3B82F6));
    final redW = segWidth(const Color(0xFFEF4444));
    expect((blueW / (blueW + redW) - 0.88).abs(), lessThan(0.01),
        reason: 'introversion segment should be 88% of the bar');

    // Reveal the lower bars one by one (ListView builds lazily).
    for (final expected in [
      {const Color(0xFF22C55E), const Color(0xFFA855F7)}, // green, purple
      {const Color(0xFFEAB308), const Color(0xFFEC4899)}, // yellow, pink
      {const Color(0xFFF97316), const Color(0xFF6366F1)}, // orange, indigo
    ]) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      final found = barColors();
      expect(found.containsAll(expected), isTrue,
          reason: 'expected $expected among $found');
      for (final color in expected) {
        expectPaintable(color);
      }
    }
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
