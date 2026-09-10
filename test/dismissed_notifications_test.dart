import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/services/dismissed_notifications.dart';

class _Store implements SessionStore {
  @override
  Future<void> clear() async {}

  @override
  Future<List<SessionCookie>> load() async => const [];

  @override
  Future<void> save(List<SessionCookie> cookies) async {}
}

void main() {
  test('only social alerts are ours to mark', () {
    expect(DismissedNotifications.bundleIdFromPayload('n:12'), 12);
    expect(DismissedNotifications.bundleIdFromPayload('c:5'), isNull,
        reason: 'a swiped message is not a read receipt for the conversation');
    expect(DismissedNotifications.bundleIdFromPayload('quote'), isNull);
    expect(DismissedNotifications.bundleIdFromPayload('n:'), isNull);
    expect(DismissedNotifications.bundleIdFromPayload('n:zero'), isNull);
    expect(DismissedNotifications.bundleIdFromPayload('n:0'), isNull);
    expect(DismissedNotifications.bundleIdFromPayload(null), isNull);
  });

  group('markRead over a real local socket', () {
    late HttpServer server;
    late ApiClient api;
    late List<String> requests;

    setUp(() async {
      requests = <String>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      api = ApiClient(
        store: _Store(),
        apiBaseUrl: 'http://127.0.0.1:${server.port}',
      );
      server.listen((req) async {
        requests.add('${req.method} ${req.uri.path}');
        if (req.uri.path == '/feed') {
          req.response.write(
              '<html><head><meta name="csrf-token" content="tok123"></head></html>');
        } else if (req.uri.path == '/api/v1/notifications') {
          requests.add('body:${await utf8.decoder.bind(req).join()}');
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode({'success': true, 'unread_count': 0}));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('the bundle behind the swipe is marked read', () async {
      await DismissedNotifications.markRead('n:12', api: api);
      expect(requests, contains('body:{"action":"mark_read","ids":[12]}'));
    });

    test('a swiped message notification sends nothing', () async {
      await DismissedNotifications.markRead('c:5', api: api);
      expect(requests, isEmpty);
    });

    test('a dead server never throws (the swipe is best-effort)', () async {
      // A port nobody is listening on: connection refused, and the
      // background isolate must swallow it instead of dying.
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = dead.port;
      await dead.close(force: true);
      await DismissedNotifications.markRead('n:12',
          api: ApiClient(
            store: _Store(),
            apiBaseUrl: 'http://127.0.0.1:$deadPort',
          ));
    });
  });
}
