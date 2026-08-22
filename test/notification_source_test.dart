import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/messages_service.dart';
import 'package:enclavd/services/message_notification_source.dart';
import 'package:enclavd/services/message_notifications.dart';
import 'package:enclavd/services/notification_source.dart';

UnreadMessage unread({
  required int id,
  required int conv,
  required String sender,
  required String text,
}) =>
    UnreadMessage(
      messageId: id,
      conversationId: conv,
      senderId: 42,
      senderName: sender,
      senderAvatar: '/a.png',
      message: text,
      createdAt: '2026-08-21 10:00:00',
    );

/// A fake source for the generic runner tests.
class _FakeSource implements NotificationSource {
  _FakeSource(this._candidates, {this.failCheck = false});

  final List<NotificationCandidate> _candidates;
  final bool failCheck;
  int checks = 0;

  @override
  String get id => 'fake';

  @override
  Future<List<NotificationCandidate>> check(SourceContext context) async {
    checks++;
    if (failCheck) throw StateError('boom');
    return _candidates;
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

SourceContext _context(SharedPreferences prefs) => SourceContext(
      api: ApiClient(store: _NoopStore(), apiBaseUrl: 'https://example.com'),
      prefs: prefs,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MessageNotificationSource.candidatesFrom', () {
    test('emits the NEWEST message per conversation', () {
      final candidates = MessageNotificationSource.candidatesFrom([
        unread(id: 101, conv: 5, sender: 'Alice', text: 'two'),
        unread(id: 100, conv: 5, sender: 'Alice', text: 'one'),
        unread(id: 77, conv: 9, sender: 'Bob', text: 'hey'),
      ]);

      expect(candidates, hasLength(2));
      final c5 = candidates.singleWhere((c) => c.key == 'message:5:101');
      expect(c5.notificationId, 5, reason: 'notification id = conversation');
      expect(c5.title, 'Alice');
      expect(c5.body, 'two');
      expect(c5.payload, 'c:5');
      expect(candidates.singleWhere((c) => c.key == 'message:9:77').body,
          'hey');
    });

    test('rejects id<=0 rows (legacy publishers emit messageId 0)', () {
      final candidates = MessageNotificationSource.candidatesFrom([
        unread(id: 0, conv: 5, sender: 'Alice', text: 'bad'),
        unread(id: 102, conv: 5, sender: 'Alice', text: 'good'),
      ]);

      expect(candidates, hasLength(1));
      expect(candidates.single.key, 'message:5:102');
    });

    test('empty input → no candidates', () {
      expect(MessageNotificationSource.candidatesFrom([]), isEmpty);
    });
  });

  group('MessageNotificationSource.check gating', () {
    test('quiet while the chat screen is open (prefs flag)', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(MessageNotificationSource.chatOpenPrefsKey, true);
      var fetched = false;
      final source = MessageNotificationSource(
          fetcher: (_) async {
            fetched = true;
            return [unread(id: 100, conv: 5, sender: 'Alice', text: 'hey')];
          });

      final candidates = await source.check(_context(prefs));

      expect(candidates, isEmpty);
      expect(fetched, isFalse, reason: 'no fetch while user is reading');
    });

    test('quiet when the master toggle is off', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(MessageNotifications.enabledPrefsKey, false);
      var fetched = false;
      final source = MessageNotificationSource(
          fetcher: (_) async {
            fetched = true;
            return [unread(id: 100, conv: 5, sender: 'Alice', text: 'hey')];
          });

      final candidates = await source.check(_context(prefs));

      expect(candidates, isEmpty);
      expect(fetched, isFalse);
    });

    test('a failing fetch returns [] — the worker must never crash',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final source = MessageNotificationSource(fetcher: (_) async {
        throw const ApiException('boom');
      });

      expect(await source.check(_context(prefs)), isEmpty);
    });
  });

  group('NotifiedTracker', () {
    test('add/contains round-trips through prefs', () async {
      final prefs = await SharedPreferences.getInstance();
      final tracker = NotifiedTracker(prefs);

      expect(tracker.contains('message:5:100'), isFalse);
      await tracker.add('message:5:100');
      expect(tracker.contains('message:5:100'), isTrue);
      expect(tracker.contains('message:9:77'), isFalse);
    });

    test('bounded: the oldest key is pruned past the cap', () async {
      final prefs = await SharedPreferences.getInstance();
      final tracker = NotifiedTracker(prefs);

      for (var i = 0; i < NotifiedTracker.maxKeys + 10; i++) {
        await tracker.add('k:$i');
      }

      expect(tracker.contains('k:0'), isFalse, reason: 'oldest pruned');
      expect(tracker.contains('k:${NotifiedTracker.maxKeys + 9}'), isTrue,
          reason: 'newest kept');
    });
  });

  group('freshCandidates', () {
    test('filters to not-yet-notified candidates and persists across runs',
        () async {
      final prefs = await SharedPreferences.getInstance();
      const candidate =
          NotificationCandidate(key: 'fake:1', notificationId: 1, title: 'T',
              body: 'B', payload: null);
      final source = _FakeSource([candidate]);
      final tracker = NotifiedTracker(prefs);

      final first = await freshCandidates([source], _context(prefs),
          tracker: tracker);
      expect(first, [candidate]);
      for (final c in first) {
        await tracker.add(c.key);
      }

      final second = await freshCandidates([source], _context(prefs),
          tracker: tracker);
      expect(second, isEmpty, reason: 'already notified → not repeated');
    });

    test('a throwing source is skipped, others still run', () async {
      final prefs = await SharedPreferences.getInstance();
      const candidate =
          NotificationCandidate(key: 'ok:1', notificationId: 1, title: 'T',
              body: 'B');
      final broken = _FakeSource(const [], failCheck: true);
      final fine = _FakeSource([candidate]);

      final fresh = await freshCandidates([broken, fine], _context(prefs));

      expect(fresh, [candidate]);
    });
  });
}
