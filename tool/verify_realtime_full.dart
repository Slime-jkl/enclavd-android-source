// Live full-loop proof for the app's realtime client (console-only).
//
// Exercises the EXACT code the phone runs — ApiClient + RealtimeService —
// against the dev stack through Apache, then verifies every live path the
// user reported broken:
//
//   1. WS connect + join           (chat receive)
//   2. message frame over WS       (chat receive — real publish via PHP)
//   3. typing frame over WS        (typing indicator — relayed by the hub
//                                   from a second client acting as the other
//                                   participant, user 3)
//   4. SSE connect + message_unread(header badge — user-targeted publish)
//
// Usage: flutter test tool/verify_realtime_full.dart   (dev stack up)
// Exit 0 = every live path reaches the app client. Prints one line per stage.
//
// Accounts: dev@dev.dev / Enclavd2026! (user 1) is the app client;
// conversation 2 is 1-on-1 with user 3 (df4fwr3).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/services/realtime_service.dart';

const base = 'https://localhost';
const conversationId = 2;
const myUserId = 1;
const otherUserId = 3;

class MemStore implements SessionStore {
  List<SessionCookie> cookies = const [];
  @override
  Future<List<SessionCookie>> load() async => cookies;
  @override
  Future<void> save(List<SessionCookie> c) async => cookies = List.of(c);
  @override
  Future<void> clear() async => cookies = [];
}

/// The app's exact HttpClient factory (default UA + dev TLS callback).
HttpClient devClient() {
  final c = HttpClient();
  c.userAgent = 'EnclavdNative/1.0';
  c.connectionTimeout = const Duration(seconds: 15);
  c.badCertificateCallback = (cert, host, port) => true; // dev self-signed
  return c;
}

Future<String> _php(String code) async {
  final r = await Process.run('docker', [
    'exec', 'Enclavd_Dev_PHP', 'php', '-r', code,
  ]);
  if (r.exitCode != 0) {
    throw StateError('php -r failed: ${r.stderr}');
  }
  return (r.stdout as String).trim();
}

Future<void> _publish(Map<String, dynamic> body) async {
  final json = jsonEncode(body);
  final code = r'''
$body = json_decode('BODY', true);
$ch = curl_init('http://Enclavd_Dev_Realtime:8090/publish');
curl_setopt_array($ch, [
  CURLOPT_POST => true,
  CURLOPT_POSTFIELDS => json_encode($body),
  CURLOPT_HTTPHEADER => [
    'Content-Type: application/json',
    'X-Publish-Secret: ' . getenv('REALTIME_SECRET'),
  ],
  CURLOPT_RETURNTRANSFER => true,
]);
echo curl_exec($ch);
'''.replaceFirst('BODY', json.replaceAll("'", "\\'"));
  final out = await _php(code);
  stdout.writeln('  publish -> $out');
}

Future<void> main() async {
  final failures = <String>[];
  final store = MemStore();
  final api = ApiClient(
    store: store,
    apiBaseUrl: base,
    httpClientFactory: devClient,
  );
  await api.restoreSession();

  final auth = AuthService(api, apiBaseUrl: base);
  final login = await auth.login(email: 'dev@dev.dev', password: 'Enclavd2026!');
  if (login.outcome != LoginOutcome.success) {
    stderr.writeln('login failed: ${login.message}');
    exit(2);
  }
  stdout.writeln('login OK (user $myUserId)');

  final realtime = RealtimeService(api, baseUrl: base, httpClientFactory: devClient);
  final gotMessage = Completer<void>();
  final gotTyping = Completer<void>();
  final gotUnread = Completer<void>();
  realtime.events.listen((e) {
    if (e.type == 'message' && e.conversationId == conversationId) {
      stdout.writeln('  [app] message frame: "${e.message}"');
      if (!gotMessage.isCompleted) gotMessage.complete();
    }
    if (e.type == 'typing' && e.conversationId == conversationId) {
      stdout.writeln('  [app] typing frame: isTyping=${e.isTyping}');
      if (e.isTyping && !gotTyping.isCompleted) gotTyping.complete();
    }
    if (e.type == 'message_unread') {
      stdout.writeln('  [app] SSE message_unread: ${e.unreadCount}');
      if (!gotUnread.isCompleted) gotUnread.complete();
    }
  });

  // ── WS ────────────────────────────────────────────────────────────────
  realtime.connectWs();
  realtime.join(conversationId);
  final wsUp = Completer<void>();
  final sub = realtime.events.listen((e) {
    if (e.type == 'history' && !wsUp.isCompleted) {
      stdout.writeln('WS connected + joined room $conversationId (history ack)');
      wsUp.complete();
    }
  });
  try {
    await wsUp.future.timeout(const Duration(seconds: 20));
  } on TimeoutException {
    failures.add('WS: no history ack (socket never authenticated/joined)');
  }
  await sub.cancel();

  // ── 1. message frame (PHP publish, excluding the sender) ─────────────
  await _publish({
    'type': 'message',
    'conversation_id': conversationId,
    'sender_id': otherUserId,
    'payload': {
      'conversationId': conversationId,
      'senderId': otherUserId,
      'messageId': 999901,
      'message': 'full-loop message proof',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    },
  });
  try {
    await gotMessage.future.timeout(const Duration(seconds: 15));
    stdout.writeln('PASS message frame');
  } on TimeoutException {
    failures.add('message frame never reached the app WS client');
  }

  // ── 2. typing frame (hub relay from a second client = user 3) ────────
  final token3 = await _php(r'''
require '/var/www/html/config/realtime.php';
echo realtime_token(3);
''');
  final ws3 = await WebSocket.connect(
    'wss://localhost/ws?token=$token3',
    customClient: devClient(),
  );
  ws3.add(jsonEncode({'type': 'join', 'conversationId': conversationId}));
  await Future<void>.delayed(const Duration(milliseconds: 500));
  ws3.add(jsonEncode({
    'type': 'typing',
    'conversationId': conversationId,
    'isTyping': true,
  }));
  try {
    await gotTyping.future.timeout(const Duration(seconds: 15));
    stdout.writeln('PASS typing frame');
  } on TimeoutException {
    failures.add('typing frame never reached the app WS client');
  }
  ws3.add(jsonEncode({
    'type': 'typing',
    'conversationId': conversationId,
    'isTyping': false,
  }));
  await ws3.close();

  // ── 3. SSE message_unread (badge, targeted at the app user) ──────────
  realtime.connectSse();
  await Future<void>.delayed(const Duration(seconds: 2)); // stream opens
  await _publish({
    'type': 'message_unread',
    'user_id': myUserId,
    'payload': {'unread_count': 42},
  });
  try {
    await gotUnread.future.timeout(const Duration(seconds: 15));
    stdout.writeln('PASS SSE message_unread');
  } on TimeoutException {
    failures.add('message_unread never reached the app SSE client');
  }

  realtime.dispose();

  if (failures.isEmpty) {
    stdout.writeln('ALL LIVE PATHS OK');
    exit(0);
  }
  stderr.writeln('FAILURES:');
  for (final f in failures) {
    stderr.writeln('  - $f');
  }
  exit(1);
}
