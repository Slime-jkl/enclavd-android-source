// Live fan-out proof for the realtime path.
// Connects the real RealtimeService to the dev sidecar as the dev account,
// joins conversation 2, and waits for a live 'message' frame. Publish the
// frame from a second process (docker exec Enclavd_Dev_PHP php -r '<json>'
// to http://Enclavd_Dev_Realtime:8090/publish with the REALTIME_SECRET).
// Usage: dart run tool/verify_realtime.dart (dev stack + login required)
// Exit 0 = the sidecar fan-out reached the app's WebSocket client.

import 'dart:async';
import 'dart:io';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/auth_service.dart';
import 'package:enclavd/services/realtime_service.dart';

class MemStore implements SessionStore {
  List<SessionCookie> cookies = const [];
  @override
  Future<List<SessionCookie>> load() async => cookies;
  @override
  Future<void> save(List<SessionCookie> c) async => cookies = List.of(c);
  @override
  Future<void> clear() async => cookies = [];
}

Future<void> main() async {
  const base = 'https://localhost';
  const conversationId = 2;
  final store = MemStore();
  final api = ApiClient(
    store: store,
    apiBaseUrl: base,
    httpClientFactory: () {
      final c = HttpClient();
      c.userAgent = 'EnclavdNative/1.0';
      c.connectionTimeout = const Duration(seconds: 15);
      c.badCertificateCallback = (cert, host, port) => true; // dev self-signed
      return c;
    },
  );
  await api.restoreSession();

  final auth = AuthService(api, apiBaseUrl: base);
  final login =
      await auth.login(email: 'dev@dev.dev', password: 'Enclavd2026!');
  if (login.outcome != LoginOutcome.success) {
    stderr.writeln('login failed: ${login.message}');
    exit(2);
  }
  // Warm the CSRF path so the rt cookie lands in the jar (a /feed fetch).
  await api.getPage('/feed');

  final realtime = RealtimeService(
    api,
    baseUrl: base,
    httpClientFactory: () {
      final c = HttpClient();
      c.userAgent = 'EnclavdNative/1.0';
      c.badCertificateCallback = (cert, host, port) => true;
      return c;
    },
  );

  final received = Completer<String>();
  realtime.events.listen((e) {
    stdout.writeln('event: ${e.type} ${e.data}');
    if (e.type == 'message' && e.conversationId == conversationId) {
      received.complete(e.message);
    }
    if (e.type == 'read') {
      stdout.writeln('read receipt: reader ${e.readerId}');
    }
  });

  realtime.join(conversationId);
  stdout.writeln('listening on conversation $conversationId - '
      'publish the inbound frame now (max 20s)');

  try {
    final message =
        await received.future.timeout(const Duration(seconds: 60));
    stdout.writeln('RECEIVED LIVE: "$message"');
    exit(0);
  } on TimeoutException {
    stderr.writeln('TIMEOUT: no message frame within 60s');
    exit(1);
  } finally {
    realtime.dispose();
  }
}
