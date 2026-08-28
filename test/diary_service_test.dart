import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/diary_service.dart';

import 'api_client_test.dart' show Harness;

Map<String, dynamic> _entryJson({
  String date = '2026-08-26',
  int mood = 3,
  String win = 'Finished the migration',
  String avoided = 'Scheduling the follow-up',
  String? tomorrow,
  String? thought,
}) =>
    {
      'date': date,
      'mood': mood,
      'mood_emoji': '\u{1F60C}',
      'mood_label': 'Steady',
      'win': win,
      'avoided': avoided,
      'tomorrow': tomorrow ?? '',
      'thought': thought ?? '',
      'created_at': '2026-08-26 21:00:00',
      'updated_at': '2026-08-26 21:00:00',
    };

void main() {
  group('DiaryService.fetchToday', () {
    test('POSTs action=get and parses an unlocked snapshot', () async {
      Map<String, dynamic>? sent;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(
              req, body: '<meta name="csrf-token" content="csrf123">');
          return;
        }
        expect(req.uri.path, '/api/v1/diary');
        sent =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'date': '2026-08-27',
            'entry': null,
            'locked': false,
            'stats': {
              'streak': 4,
              'longest_streak': 9,
              'total_entries': 12,
              'moods_30d': {'1': 3, '2': 0, '3': 4, '4': 2, '5': 3},
            },
            'recent': [_entryJson()],
          }),
        );
      });

      final s = await DiaryService(h.client).fetchToday();
      expect(sent, {'action': 'get'});
      expect(s.date, '2026-08-27');
      expect(s.locked, isFalse);
      expect(s.entry, isNull);
      expect(s.stats.streak, 4);
      expect(s.stats.longestStreak, 9);
      expect(s.stats.totalEntries, 12);
      expect(s.stats.moods30d, {1: 3, 2: 0, 3: 4, 4: 2, 5: 3});
      expect(s.recent, hasLength(1));
      expect(s.recent.single.win, 'Finished the migration');
      expect(s.recent.single.moodEmoji, '\u{1F60C}');
      expect(s.recent.single.moodLabel, 'Steady');
      expect(s.recent.single.avoided, 'Scheduling the follow-up');
      await h.close();
    });

    test('parses a locked snapshot with today\'s entry', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
          return;
        }
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'date': '2026-08-27',
            'entry': _entryJson(
                date: '2026-08-27', mood: 5, win: 'Shipped the app',
                avoided: '', tomorrow: 'Wake up earlier',
                thought: 'What makes a habit stick'),
            'locked': true,
            'stats': {
              'streak': 1,
              'longest_streak': 1,
              'total_entries': 1,
              'moods_30d': {'1': 0, '2': 0, '3': 0, '4': 0, '5': 1},
            },
            'recent': <Object>[],
          }),
        );
      });

      final s = await DiaryService(h.client).fetchToday();
      expect(s.locked, isTrue);
      final e = s.entry!;
      expect(e.mood, 5);
      expect(e.moodLabel, 'Steady');
      expect(e.win, 'Shipped the app');
      expect(e.avoided, '');
      expect(e.tomorrow, 'Wake up earlier');
      expect(e.thought, 'What makes a habit stick');
      expect(s.recent, isEmpty);
      await h.close();
    });

    test('4xx surfaces the server message verbatim', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
          return;
        }
        Harness.respond(
            req,
            status: 400,
            body: '{"error":"Pick a mood for today."}');
      });
      await expectLater(
        DiaryService(h.client).fetchToday(),
        throwsA(isA<ApiException>()
            .having((e) => e.status, 'status', 400)
            .having((e) => e.message, 'message', 'Pick a mood for today.')),
      );
      await h.close();
    });
  });

  group('DiaryService.saveToday', () {
    test('POSTs action=save with all fields and parses the prestige math',
        () async {
      Map<String, dynamic>? sent;
      String? csrfHeader;
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(
              req, body: '<meta name="csrf-token" content="tok-123">');
          return;
        }
        expect(req.uri.path, '/api/v1/diary');
        csrfHeader = req.headers.value('x-csrf-token');
        sent =
            jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'date': '2026-08-27',
            'entry': _entryJson(
                date: '2026-08-27',
                mood: 4,
                win: 'Closed three tickets'),
            'locked': false,
            'stats': {
              'streak': 1,
              'longest_streak': 1,
              'total_entries': 1,
              'moods_30d': {'1': 0, '2': 0, '3': 0, '4': 1, '5': 0},
            },
            'prestige': {'awarded': 2, 'penalty': 4, 'missed_days': 2, 'net': 0},
          }),
        );
      });

      final r = await DiaryService(h.client).saveToday(
        mood: 4,
        win: 'Closed three tickets',
        avoided: 'The refactor',
        tomorrow: 'Ship the build',
        thought: 'Why we procrastinate',
      );
      expect(csrfHeader, 'tok-123');
      expect(sent, {
        'action': 'save',
        'mood': 4,
        'win': 'Closed three tickets',
        'avoided': 'The refactor',
        'tomorrow': 'Ship the build',
        'thought': 'Why we procrastinate',
      });
      expect(r.entry.mood, 4);
      expect(r.locked, isFalse);
      expect(r.prestige.awarded, 2);
      expect(r.prestige.penalty, 4);
      expect(r.prestige.missedDays, 2);
      expect(r.prestige.net, 0);
      await h.close();
    });

    test('a repeated same-day save parses as an idempotent no-op', () async {
      final h = await Harness.start((req) async {
        if (req.uri.path == '/feed') {
          Harness.respond(req, body: '<meta name="csrf-token" content="t">');
          return;
        }
        await utf8.decodeStream(req);
        Harness.respond(
          req,
          body: jsonEncode({
            'success': true,
            'date': '2026-08-27',
            'entry': _entryJson(
                date: '2026-08-27', mood: 2, win: 'Untangled the merge'),
            'locked': true,
            'stats': {
              'streak': 2,
              'longest_streak': 5,
              'total_entries': 8,
              'moods_30d': {'1': 1, '2': 2, '3': 3, '4': 1, '5': 1},
            },
            'prestige': {'awarded': 0, 'penalty': 0, 'missed_days': 0, 'net': 0},
          }),
        );
      });

      final r = await DiaryService(h.client).saveToday(
          mood: 2, win: 'Untangled the merge');
      expect(r.locked, isTrue);
      expect(r.prestige.net, 0);
      await h.close();
    });
  });
}
