import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/diary_service.dart';
import 'package:enclavd/screens/diary_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/utils/user_facing_errors.dart';

class _FakeDiary extends DiaryService {
  _FakeDiary({
    this.snapshot,
    this.saveResult,
    this.error,
    this.onSave,
  }) : super(ApiClient(
            store: _NoopStore(), apiBaseUrl: 'https://example.com'));

  DiarySnapshot? snapshot;
  DiarySaveResult? saveResult;
  ApiException? error;
  final void Function(Map<String, dynamic> body)? onSave;
  int fetchCalls = 0;

  @override
  Future<DiarySnapshot> fetchToday() async {
    fetchCalls++;
    if (error != null) throw error!;
    return snapshot!;
  }

  @override
  Future<DiarySaveResult> saveToday({
    required int mood,
    required String win,
    String avoided = '',
    String tomorrow = '',
    String thought = '',
  }) async {
    onSave?.call({
      'mood': mood,
      'win': win,
      'avoided': avoided,
      'tomorrow': tomorrow,
      'thought': thought,
    });
    if (saveResult == null) {
      throw const ApiException('No save result', status: 500);
    }
    return saveResult!;
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

DiaryEntry _entry({
  String date = '2026-08-26',
  int mood = 3,
  String moodEmoji = '😌',
  String moodLabel = 'Steady',
  String win = 'Fixed the login bug',
  String avoided = '',
  String tomorrow = '',
  String thought = '',
}) =>
    DiaryEntry(
      date: date,
      mood: mood,
      moodEmoji: moodEmoji,
      moodLabel: moodLabel,
      win: win,
      avoided: avoided,
      tomorrow: tomorrow,
      thought: thought,
      createdAt: '$date 21:00:00',
      updatedAt: '$date 21:00:00',
    );

DiaryStats _stats({int total = 12}) => DiaryStats(
      streak: 4,
      longestStreak: 9,
      totalEntries: total,
      moods30d: const {1: 3, 2: 0, 3: 4, 4: 2, 5: 3},
    );

DiarySnapshot _unlocked({int total = 12}) => DiarySnapshot(
      date: '2026-08-27',
      entry: null,
      locked: false,
      stats: _stats(total: total),
      recent: [_entry(), _entry(date: '2026-08-25', win: 'Paid the invoice')],
    );

DiarySnapshot _locked() => DiarySnapshot(
      date: '2026-08-27',
      entry: _entry(
        date: '2026-08-27',
        mood: 5,
        moodEmoji: '🔥',
        moodLabel: 'Unstoppable',
        win: 'Shipped the release',
        avoided: 'Procrastinating',
        thought: 'Habit design',
      ),
      locked: true,
      stats: _stats(total: 13),
      recent: [
        _entry(
          date: '2026-08-27',
          mood: 5,
          moodEmoji: '🔥',
          moodLabel: 'Unstoppable',
          win: 'Shipped the release',
          avoided: 'Procrastinating',
          thought: 'Habit design',
        ),
        _entry(),
      ],
    );

Future<void> _pump(WidgetTester tester, DiaryService diary) async {
  // Phone-sized viewport: the stats + mood strip sit above the entry
  // card now, so the wizard and the recent list must be reachable on a
  // tall screen (default 800x600 would push wizard buttons off-screen).
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildEnclavdTheme(),
    home: DiaryScreen(diary: diary),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Scroll a target into view before tapping it — the stats + mood strip
/// now sit above the entry card, so wizard buttons can start below the
/// 600px test viewport fold.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('unlocked diary renders the wizard, stats and recent entries',
      (tester) async {
    await _pump(tester, _FakeDiary(snapshot: _unlocked()));

    expect(find.text('Diary'), findsOneWidget); // app bar
    expect(find.text("Today's diary"), findsOneWidget);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('Welcome to Diary'), findsNothing);
    expect(find.textContaining('Pick how today went'), findsOneWidget);
    // All five moods are tappable (uppercase labels, like the site).
    for (final label in ['ROUGH', 'FLAT', 'STEADY', 'GRINDING', 'UNSTOPPABLE']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Tap a mood…'), findsOneWidget);

    // Stats + strip are at the top now (the modern layout).
    expect(find.text('4'), findsOneWidget); // day streak
    expect(find.text('9'), findsOneWidget); // best streak
    expect(find.text('12'), findsOneWidget); // entries
    expect(find.text('Mood · last 30 days'), findsOneWidget);

    // Recent entries below the fold.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(find.text('Recent entries'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Fixed the login bug'), findsOneWidget);
  });

  testWidgets('first-time users get the Before you start warning step',
      (tester) async {
    await _pump(tester, _FakeDiary(snapshot: _unlocked(total: 0)));

    expect(find.text('Step 1 of 6'), findsOneWidget);
    expect(find.text('Before you start'), findsOneWidget);
    expect(find.textContaining('Starting a Journal is a commitment'),
        findsOneWidget);
    expect(find.text('I understand. Start my journal'), findsOneWidget);

    await _tap(tester, find.text('I understand. Start my journal'));
    expect(find.text('Step 2 of 6'), findsOneWidget);
    expect(find.textContaining('Pick how today went'), findsOneWidget);
  });

  testWidgets('mood and win are required with the site texts', (tester) async {
    await _pump(tester, _FakeDiary(snapshot: _unlocked()));

    // No mood picked → the site's exact message.
    await _tap(tester, find.text('Start'));
    expect(find.text('Pick a mood for today.'), findsOneWidget);

    // Picking a mood clears the error and shows its hint.
    await _tap(tester, find.text('GRINDING'));
    expect(find.text('Pick a mood for today.'), findsNothing);
    expect(find.text('Locked in and pushing.'), findsOneWidget);

    // Straight to the win step, then Next without a win → site message.
    await _tap(tester, find.text('Start'));
    expect(find.text('What was a small win you achieved today?'), findsOneWidget);
    expect(find.text('REQUIRED'), findsOneWidget);
    await _tap(tester, find.text('Next'));
    expect(find.text('Name one small win. Even a tiny one counts.'),
        findsOneWidget);

    // A win unlocks the next step (optional fields have no gate).
    await tester.enterText(find.byType(TextField), 'Closed three tickets');
    await _tap(tester, find.text('Next'));
    expect(find.text('What are you avoiding?'), findsOneWidget);
    expect(find.text('OPTIONAL'), findsOneWidget);
  });

  testWidgets('locking in saves the entry and shows the locked hero',
      (tester) async {
    Map<String, dynamic>? sent;
    final diary = _FakeDiary(
      snapshot: _unlocked(),
      onSave: (body) => sent = body,
      saveResult: DiarySaveResult(
        date: '2026-08-27',
        entry: _entry(
          date: '2026-08-27',
          mood: 3,
          win: 'Closed three tickets',
          avoided: 'The refactor',
        ),
        locked: false,
        stats: _stats(total: 13),
        prestige: const DiaryPrestige(
            awarded: 2, penalty: 0, missedDays: 0, net: 2),
      ),
    );
    await _pump(tester, diary);

    await _tap(tester, find.text('STEADY'));
    await _tap(tester, find.text('Start'));
    await tester.enterText(find.byType(TextField), 'Closed three tickets');
    await _tap(tester, find.text('Next'));
    await tester.enterText(find.byType(TextField), 'The refactor');
    await _tap(tester, find.text('Next'));
    // Optional steps pass through freely.
    await _tap(tester, find.text('Next'));
    await _tap(tester, find.text('Lock it in'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(sent, {
      'mood': 3,
      'win': 'Closed three tickets',
      'avoided': 'The refactor',
      'tomorrow': '',
      'thought': '',
    });
    expect(find.text('Locked in.'), findsOneWidget);
    expect(find.text('See you tomorrow.'), findsOneWidget);
    expect(find.text('This entry earned you +2 prestige.'), findsOneWidget);
    // The summary card is gone (site parity): no mood label anywhere.
    expect(find.text('Steady'), findsNothing);
    expect(find.text("Today's mood"), findsNothing);

    // Today's answers now live in the expanded Recent entries row.
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(find.text('SMALL WIN'), findsWidgets);
    expect(find.text('Closed three tickets'), findsWidgets);
    expect(find.text('AVOIDING'), findsWidgets);
    expect(find.text('The refactor'), findsWidgets);
  });

  testWidgets('a locked day renders the lock, stats, strip and recent',
      (tester) async {
    await _pump(tester, _FakeDiary(snapshot: _locked()));

    expect(find.text('Locked in.'), findsOneWidget);
    // Date label on the locked card + the expanded recent row for today.
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Unstoppable'), findsNothing); // mood label not shown
    expect(find.text("Today's mood"), findsNothing);

    // Stats + strip are at the top now — visible without scrolling.
    expect(find.text('13'), findsOneWidget); // entries stat
    expect(find.text('Mood · last 30 days'), findsOneWidget);

    // Today's answers render in the expanded recent row (only filled
    // fields; tomorrow was left empty).
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pump();
    expect(find.text('Recent entries'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Fixed the login bug'), findsOneWidget);
    expect(find.text('SMALL WIN'), findsWidgets);
    expect(find.text('AVOIDING'), findsWidgets);
    expect(find.text('THOUGHT EXPLORED'), findsWidgets);
    expect(find.text('TOMORROW'), findsNothing);
  });

  testWidgets('load failure shows the friendly error view; retry reloads',
      (tester) async {
    final diary = _FakeDiary(
        error: const ApiException('No network. Check your connection and try again.'));
    await _pump(tester, diary);

    // Status-null ApiExceptions map to the standard internal-error line
    // (the app's user-facing error contract — same as every other screen).
    expect(find.text(kInternalError), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text("Today's diary"), findsNothing);

    diary.error = null;
    diary.snapshot = _unlocked();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(diary.fetchCalls, 2);
    expect(find.text("Today's diary"), findsOneWidget);
  });
}
