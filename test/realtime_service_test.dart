import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/services/realtime_service.dart';

/// In-memory cookie store (same seam as the other service tests).
class MemStore implements SessionStore {
  MemStore([List<SessionCookie>? seed]) : cookies = seed ?? [];
  List<SessionCookie> cookies;

  @override
  Future<List<SessionCookie>> load() async => cookies;

  @override
  Future<void> save(List<SessionCookie> c) async => cookies = List.of(c);

  @override
  Future<void> clear() async => cookies = [];
}

/// A local realtime server: /ws (WebSocket), /feed (issues the rt cookie),
/// /events (SSE). Genuine sockets — the same verification style as the
/// api_client_test Harness, exercising the REAL wire path.
class RealtimeHarness {
  RealtimeHarness._(this.server, this.handlers);

  final HttpServer server;
  final Map<String, dynamic> handlers;

  int wsConnects = 0;
  final List<String> wsTokens = [];
  final List<List<Map<String, dynamic>>> wsFrames = []; // per connection
  final List<WebSocket> wsClients = [];
  bool dropOnConnect = false;
  bool respondToPing = true; // reply {type:'pong'} to client {type:'ping'}
  int pongsSent = 0;
  final List<String> feedRequests = [];
  final List<String> sseRequests = [];
  int feedFailures = 0; // answer the next N /feed requests with 500
  int sseFailures = 0; // answer the next N /events requests with 500
  bool keepSseOpen = false; // keep the SSE stream open (no close)

  int get port => server.port;

  static Future<RealtimeHarness> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final h = RealtimeHarness._(server, {});
    server.listen((req) async {
      if (req.uri.path == '/ws') {
        h.wsConnects++;
        h.wsTokens.add(req.uri.queryParameters['token'] ?? '');
        final ws = await WebSocketTransformer.upgrade(req);
        if (h.dropOnConnect) {
          await ws.close();
          return;
        }
        h.wsClients.add(ws);
        final frames = <Map<String, dynamic>>[];
        h.wsFrames.add(frames);
        ws.listen(
          (data) {
            if (data is String) {
              try {
                final frame = jsonDecode(data) as Map<String, dynamic>;
                frames.add(frame);
                if (h.respondToPing && frame['type'] == 'ping') {
                  h.pongsSent++;
                  ws.add(jsonEncode({'type': 'pong'}));
                }
              } catch (_) {}
            }
          },
          onDone: () => h.wsClients.remove(ws),
        );
      } else if (req.uri.path == '/feed') {
        h.feedRequests.add(req.uri.path);
        if (h.feedFailures > 0) {
          h.feedFailures--;
          req.response.statusCode = HttpStatus.internalServerError;
          await req.response.close();
          return;
        }
        req.response.headers.set(
          'set-cookie',
          'enclavd_rt=1.9999999999.abcdef; Path=/; HttpOnly',
        );
        req.response.write('<meta name="csrf-token" content="t">');
        await req.response.close();
      } else if (req.uri.path == '/events') {
        h.sseRequests.add(req.uri.queryParameters['token'] ?? '');
        if (h.sseFailures > 0) {
          h.sseFailures--;
          req.response.statusCode = HttpStatus.internalServerError;
          await req.response.close();
          return;
        }
        req.response.headers.set('content-type', 'text/event-stream');
        if (h.keepSseOpen) {
          // Write an initial heartbeat so the response is committed —
          // flush() alone on an empty body never sends the headers in
          // dart:io, and the client would hang in request.close().
          req.response.write(': ping\n\n');
          await req.response.flush();
          return; // stream stays open — no events, no close
        }
        req.response.write('event: message_unread\n'
            'data: {"unread_count":3}\n\n'
            ': ping\n\n'
            'event: message_unread\n'
            'data: {"unread_count":0}\n\n');
        await req.response.close();
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    });
    return h;
  }

  /// Pushes a frame to every connected client (server → client path).
  void broadcast(Map<String, dynamic> frame) {
    final text = jsonEncode(frame);
    for (final ws in List.of(wsClients)) {
      ws.add(text);
    }
  }

  Future<void> close() async {
    for (final ws in List.of(wsClients)) {
      await ws.close();
    }
    await server.close(force: true);
  }
}

Future<RealtimeService> buildService(RealtimeHarness h,
    {MemStore? store,
    Duration pongTimeout = const Duration(seconds: 4)}) async {
  final api = ApiClient(
    store: store ?? MemStore(),
    apiBaseUrl: 'http://127.0.0.1:${h.port}',
  );
  await api.restoreSession(); // load the seeded jar like the app does
  return RealtimeService(
    api,
    baseUrl: 'http://127.0.0.1:${h.port}',
    reconnectDelay: const Duration(milliseconds: 20),
    pongTimeout: pongTimeout,
  );
}

/// Map equality for frames decoded from JSON (Dart Map == is identity).
bool hasFrame(List<Map<String, dynamic>> frames, Map<String, dynamic> want) =>
    frames.any((f) =>
        want.keys.every((k) => f[k] == want[k]) && f.length == want.length);

void main() {
  test('connectWs authenticates with the jar token and joins rooms',
      () async {
    final h = await RealtimeHarness.start();
    final store = MemStore([
      const SessionCookie(name: 'enclavd_rt', value: '7.9999999999.token'),
      const SessionCookie(name: 'sid', value: 'x'),
    ]);
    final service = await buildService(h, store: store);

    service.join(42); // records the room, triggers the connect
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(h.wsConnects, 1);
    expect(h.wsTokens.single, '7.9999999999.token');
    expect(hasFrame(h.wsFrames.single, {'type': 'join', 'conversationId': 42}), isTrue);

    service.dispose();
    await h.close();
  });

  test('missing jar token refreshes it via GET /feed', () async {
    final h = await RealtimeHarness.start();
    final service = await buildService(h); // empty store — no rt cookie

    service.join(42);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(h.feedRequests, isNotEmpty, reason: '/feed must be fetched');
    expect(h.wsTokens.single, '1.9999999999.abcdef',
        reason: 'token from the /feed Set-Cookie');

    service.dispose();
    await h.close();
  });

  test('a failed token refresh retries instead of giving up', () async {
    final h = await RealtimeHarness.start();
    h.feedFailures = 1; // first /feed answers 500, second succeeds
    final service = await buildService(h); // empty jar — token fetch needed

    service.join(42);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(h.feedRequests.length, greaterThanOrEqualTo(2),
        reason: 'a 500 on the token refresh must not end the attempt');
    expect(h.wsConnects, 1, reason: 'the retried attempt connects');
    expect(h.wsTokens.single, '1.9999999999.abcdef',
        reason: 'token from the successful retry');

    service.dispose();
    await h.close();
  });

  test('server-pushed message frame surfaces as a parsed event', () async {
    final h = await RealtimeHarness.start();
    final service = await buildService(h);

    final received = <RealtimeEvent>[];
    final done = Completer<void>();
    service.events.listen((e) {
      received.add(e);
      if (e.type == 'message') done.complete();
    });

    service.join(7);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    h.broadcast({
      'type': 'message',
      'conversationId': 7,
      'senderId': 42,
      'messageId': 300,
      'message': 'live ping',
      'timestamp': '2026-08-20T10:00:00+00:00',
    });
    await done.future.timeout(const Duration(seconds: 2));

    expect(received, hasLength(1));
    expect(received.single.type, 'message');
    expect(received.single.conversationId, 7);
    expect(received.single.senderId, 42);
    expect(received.single.messageId, 300);
    expect(received.single.message, 'live ping');

    service.dispose();
    await h.close();
  });

  test('sendTyping forwards the frame to the room', () async {
    final h = await RealtimeHarness.start();
    final service = await buildService(h);

    service.join(7);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    service.sendTyping(7, true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final frames = h.wsFrames.single;
    expect(hasFrame(frames, {'type': 'typing', 'conversationId': 7, 'isTyping': true}), isTrue);

    service.dispose();
    await h.close();
  });

  test('reconnect re-joins tracked rooms', () async {
    final h = await RealtimeHarness.start();
    final service = await buildService(h);

    service.join(42);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final firstConnections = h.wsConnects;

    // Kill every socket — the service must reconnect and re-send the join.
    for (final ws in List.of(h.wsClients)) {
      await ws.close();
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(h.wsConnects, greaterThan(firstConnections));
    final lastFrames = h.wsFrames.last;
    expect(hasFrame(lastFrames, {'type': 'join', 'conversationId': 42}), isTrue,
        reason: 'reconnect must replay the join frame');

    service.dispose();
    await h.close();
  });

  test('WS reconnects indefinitely — never gives up while the app is alive',
      () async {
    final h = await RealtimeHarness.start();
    h.dropOnConnect = true; // every connection dies immediately
    final service = await buildService(h);

    service.join(42);
    // Old behavior: initial connect + 5 attempts, then silence forever
    // (chat deaf until a screen calls connectWs()). New behavior: retries
    // forever, backoff grows 20ms → 200ms after the first 5.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(h.wsConnects, greaterThan(RealtimeService.maxReconnectAttempts + 1),
        reason: 'the WS must still be retrying past the old 5-attempt budget');

    service.dispose();
    await h.close();
  });

  test('onForeground probes a live socket with ping/pong and keeps it',
      () async {
    final h = await RealtimeHarness.start();
    final service = await buildService(h);

    service.join(7);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await service.onForeground();

    expect(h.pongsSent, greaterThanOrEqualTo(1),
        reason: 'the resume probe must ping the socket');
    expect(h.wsConnects, 1, reason: 'a live socket must NOT be reconnected');
    expect(service.isWsConnected, isTrue);

    service.dispose();
    await h.close();
  });

  test('onForeground detects a zombie socket (no pong) and reconnects now',
      () async {
    final h = await RealtimeHarness.start();
    final service = await buildService(h,
        pongTimeout: const Duration(milliseconds: 30));

    service.join(42);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    h.respondToPing = false; // server stops answering — half-open zombie
    await service.onForeground();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(h.wsConnects, greaterThanOrEqualTo(2),
        reason: 'a zombie socket must be closed and reconnected immediately');
    final lastFrames = h.wsFrames.last;
    expect(hasFrame(lastFrames, {'type': 'join', 'conversationId': 42}), isTrue,
        reason: 'the fresh connection replays the join');

    service.dispose();
    await h.close();
  });

  test('onForeground connects when no socket exists (cold resume)', () async {
    final h = await RealtimeHarness.start();
    final service = await buildService(h);

    await service.onForeground();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(h.wsConnects, 1);
    expect(service.isWsConnected, isTrue);

    service.dispose();
    await h.close();
  });

  test('SSE message_unread events parse; heartbeats are ignored', () async {
    final h = await RealtimeHarness.start();
    final service = await buildService(h);

    final received = <RealtimeEvent>[];
    final done = Completer<void>();
    service.events.listen((e) {
      received.add(e);
      if (received.length == 2) done.complete();
    });

    await service.connectSse();
    await done.future.timeout(const Duration(seconds: 2));

    expect(h.sseRequests.first, '1.9999999999.abcdef',
        reason: 'token from the /feed cookie');
    expect(received, hasLength(2));
    expect(received[0].type, 'message_unread');
    expect(received[0].unreadCount, 3);
    expect(received[1].unreadCount, 0);
    expect(received.map((e) => e.type), everyElement('message_unread'));

    service.dispose();
    await h.close();
  });

  test('SSE reconnects indefinitely — the badge stream never gives up',
      () async {
    final h = await RealtimeHarness.start();
    h.sseFailures = 10; // more than the old 5-attempt budget
    final service = await buildService(h);
    final done = Completer<void>();
    service.events.listen((e) {
      if (e.type == 'message_unread' && !done.isCompleted) done.complete();
    });

    await service.connectSse();
    await done.future.timeout(const Duration(seconds: 3));

    expect(h.sseRequests.length, greaterThan(RealtimeService.maxReconnectAttempts),
        reason: '10 failures → the 11th attempt connects (no give-up)');

    service.dispose();
    await h.close();
  });

  test('connectSse is a no-op while a stream is already active', () async {
    final h = await RealtimeHarness.start();
    h.keepSseOpen = true;
    final service = await buildService(h);

    // Do NOT await the first connect: with the stream kept open it only
    // returns when the stream ends — that is exactly the live state the
    // second call must detect.
    unawaited(service.connectSse());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await service.connectSse(); // must return immediately (stream active)
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(h.sseRequests, hasLength(1), reason: 'one live stream only');

    service.dispose();
    await h.close();
  });

  test('isSseConnected tracks the stream state (badge poll gates on it)',
      () async {
    final h = await RealtimeHarness.start();
    h.keepSseOpen = true; // stream stays open (no close)
    final service = await buildService(h);

    expect(service.isSseConnected, isFalse);
    unawaited(service.connectSse());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(service.isSseConnected, isTrue,
        reason: 'an open stream must read as connected');

    service.dispose();
    expect(service.isSseConnected, isFalse,
        reason: 'dispose closes the stream');

    await h.close();
  });

  test('dispose closes the socket and stops reconnects', () async {
    final h = await RealtimeHarness.start();
    final service = await buildService(h);

    service.join(7);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    service.dispose();

    final connectsAtDispose = h.wsConnects;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(h.wsConnects, connectsAtDispose, reason: 'no reconnect after dispose');

    await h.close();
  });
}
