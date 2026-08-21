import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../api/api_client.dart';
import '../config/app_config.dart';

/// One parsed realtime frame (WebSocket or SSE), the app's unified event.
///
/// The sidecar (services/realtime) is a DUMB TRANSPORT: PHP publishes after
/// its DB write, the Go hub fans out to WebSocket rooms (chat) and SSE
/// streams (badges/notifications). Field names follow the sidecar's wire
/// protocol (docs/realtime/protocol.md) — camelCase on WS frames,
/// snake_case in SSE payloads (e.g. message_unread → unread_count).
class RealtimeEvent {
  const RealtimeEvent({required this.type, this.data = const {}});

  /// 'message' | 'typing' | 'read' | 'presence' | 'conversation_update' |
  /// 'history' | 'error' | 'message_unread' | 'notification' | 'new_post'
  final String type;
  final Map<String, dynamic> data;

  int? get conversationId => (data['conversationId'] as num?)?.toInt();
  int? get senderId => (data['senderId'] as num?)?.toInt();
  int? get messageId => (data['messageId'] as num?)?.toInt();
  int? get readerId => (data['readerId'] as num?)?.toInt();
  int? get userId => (data['userId'] as num?)?.toInt();
  String get message => data['message'] as String? ?? '';
  bool get isTyping => data['isTyping'] as bool? ?? false;
  int? get unreadCount => (data['unread_count'] as num?)?.toInt();
  String get errorMessage => data['message'] as String? ?? '';

  @override
  String toString() => 'RealtimeEvent($type, $data)';
}

/// RealtimeService — the app's WebSocket + SSE client for the Go sidecar.
///
/// Architecture (mirrors the site): WebSocket is the LIVE path for chat
/// (message/typing/read frames, room join/leave), SSE is the LIVE path for
/// the header badge (message_unread). REST stays the source of truth and
/// the fallback: the screens keep their polls, exactly like the site's
/// "WS primary + 30s poll fallback" design.
///
/// Auth: the sidecar accepts `?token=` for non-browser clients. The token
/// (enclavd_rt, "<uid>.<expiry>.<hmac>") is issued by PHP on every logged-in
/// page render and lands in the app's cookie jar on the /feed fetches the
/// ApiClient already makes. [connect] reads it from the jar and refreshes
/// it via GET /feed when missing or within 5 minutes of expiry.
///
/// Reliability: reconnect FOREVER while the app is alive — Android drops
/// idle sockets in the background, so a hard attempt budget would leave the
/// chat deaf until a screen happens to reconnect. Backoff grows 3s → 30s
/// (like SSE); rooms are re-joined on every reconnect. [connectWs] and
/// [onForeground] (app lifecycle resume) reset the backoff and reconnect
/// immediately, so bringing the app back feels instant. The REST polls
/// remain as the fallback whenever the socket is down.
class RealtimeService {
  RealtimeService(
    this._api, {
    String? baseUrl,
    HttpClient Function()? httpClientFactory,
    Duration reconnectDelay = const Duration(seconds: 3),
    Duration pongTimeout = const Duration(seconds: 4),
  })  : _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _httpClientFactory = httpClientFactory ?? _defaultHttpClient,
        _reconnectDelay = reconnectDelay,
        _pongTimeout = pongTimeout;

  final ApiClient _api;
  final String _baseUrl;
  final HttpClient Function() _httpClientFactory;
  final Duration _reconnectDelay;

  /// How long [onForeground]'s liveness probe waits for a pong before
  /// declaring the socket dead and reconnecting. 4s on device; tests pass
  /// a tiny value.
  final Duration _pongTimeout;

  /// Backoff knee: the first 5 failures wait [reconnectDelay] each, then
  /// the wait grows to [reconnectDelay] × 10 (3s → 30s on prod). NOT a
  /// hard cap — the WS reconnects indefinitely while the app is alive.
  static const int maxReconnectAttempts = 5;
  static const Duration pingInterval = Duration(seconds: 30);
  static const Duration tokenRefreshSkew = Duration(minutes: 5);

  static HttpClient _defaultHttpClient() {
    final client = HttpClient();
    client.userAgent = AppConfig.userAgent;
    client.connectionTimeout = AppConfig.connectTimeout;
    if (AppConfig.allowInsecureTls) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }

  /// Unified event stream (WS frames + SSE events). Broadcast: late
  /// listeners only see events after subscribing.
  final _events = StreamController<RealtimeEvent>.broadcast();
  Stream<RealtimeEvent> get events => _events.stream;

  // ── WebSocket state ──────────────────────────────────────────────────
  WebSocket? _ws;
  bool _wsConnecting = false;
  int _wsAttempts = 0;
  Timer? _wsReconnectTimer;
  Timer? _wsPingTimer;

  /// Rooms this client wants to hear. Replayed as join frames on every
  /// (re)connect so a reconnect never leaves a screen deaf.
  final Set<int> _joined = {};

  // ── SSE state ────────────────────────────────────────────────────────
  bool _sseConnecting = false;
  int _sseAttempts = 0;
  Timer? _sseReconnectTimer;
  HttpClient? _sseClient;

  bool _disposed = false;

  bool get isWsConnected => _ws != null;

  /// True while the SSE stream is open. The badge poll gates on this —
  /// while the stream is live the badge is event-driven (site parity:
  /// `EnclavdRealtime.connected`); the poll only runs as the dead-stream
  /// fallback.
  bool get isSseConnected => _sseClient != null;

  bool get isConnecting => _wsConnecting || _sseConnecting;

  /// Opens the WebSocket (idempotent). An explicit call from a screen
  /// resets the reconnect budget — a fresh attempt after the service gave
  /// up is always allowed.
  Future<void> connectWs() async {
    if (_disposed) return;
    _wsAttempts = 0;
    await _connectWs();
  }

  Future<void> _connectWs() async {
    if (_disposed || _ws != null || _wsConnecting) return;
    _wsConnecting = true;
    try {
      final token = await _token();
      if (token == null) {
        // Token fetch failed (cold jar, transient /feed refresh blip) —
        // schedule a retry like any other failure; never give up silently
        // or the screen stays deaf for the whole session.
        _wsConnecting = false;
        _scheduleWsReconnect();
        return;
      }
      final client = _httpClientFactory();
      final url = _wsUri(token).toString();
      final ws = await WebSocket.connect(url, customClient: client);
      if (_disposed) {
        await ws.close();
        return;
      }
      _ws = ws;
      _wsConnecting = false;
      // The backoff is NOT reset here — a connection that drops right
      // after the handshake must keep backing off, or an unstable link
      // would hammer the server. The backoff resets on an explicit
      // connectWs() (a screen opening a chat) or onForeground() (app
      // resume — coming back to the app should reconnect immediately).
      // Re-join every tracked room (covers the first connect too).
      for (final conversationId in _joined) {
        _sendWs({'type': 'join', 'conversationId': conversationId});
      }
      _wsPingTimer?.cancel();
      _wsPingTimer =
          Timer.periodic(pingInterval, (_) => _sendWs({'type': 'ping'}));
      ws.listen(_onWsData, onError: (_) => _onWsClosed(), onDone: _onWsClosed);
    } on WebSocketException {
      _wsConnecting = false;
      _scheduleWsReconnect();
    } on SocketException {
      _wsConnecting = false;
      _scheduleWsReconnect();
    } catch (_) {
      _wsConnecting = false;
      _scheduleWsReconnect();
    }
  }

  void _onWsData(dynamic raw) {
    if (raw is! String) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _events.add(RealtimeEvent(
          type: decoded['type'] as String? ?? '',
          data: decoded,
        ));
      }
    } catch (_) {
      // Malformed frame — drop (the sidecar is a dumb transport; REST
      // reconciliation on the next poll fixes any gap).
    }
  }

  void _onWsClosed() {
    _wsPingTimer?.cancel();
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    _scheduleWsReconnect();
  }

  void _scheduleWsReconnect() {
    if (_disposed) return;
    _wsReconnectTimer?.cancel();
    // EventSource-style: the WS reconnects FOREVER while the app is alive.
    // Android drops idle sockets in the background and the user expects the
    // chat to come back on its own — a hard budget would leave it deaf until
    // a screen happens to call connectWs() again. Backoff grows past the
    // first attempts so a dead network doesn't hammer; connectWs() and
    // onForeground() reset the backoff.
    final delay = _wsAttempts < maxReconnectAttempts
        ? _reconnectDelay
        : _reconnectDelay * 10; // prod: 3s -> 30s; tests scale too
    _wsAttempts++;
    _wsReconnectTimer = Timer(delay, _connectWs);
  }

  /// App lifecycle resume (foreground). The OS froze timers and likely
  /// dropped the socket while backgrounded, so:
  ///   - no socket       → connect now (backoff reset),
  ///   - open socket     → ping it; if no pong within [_pongTimeout] it is
  ///                       a zombie (TCP half-open — the OS doesn't tell us)
  ///                       → close and reconnect NOW instead of waiting up
  ///                       to 30s for the next ping write to fail,
  ///   - SSE down        → reconnect it too.
  /// Idempotent and safe to call from any screen's lifecycle observer.
  Future<void> onForeground() async {
    if (_disposed) return;
    _wsReconnectTimer?.cancel();
    if (_ws == null) {
      if (!_wsConnecting) await connectWs();
    } else {
      final alive = await _probeWs();
      if (!alive && !_disposed && _ws != null) {
        // Zombie socket: force the normal close path, then reconnect
        // immediately (fresh backoff).
        _wsPingTimer?.cancel();
        try {
          _ws?.close();
        } catch (_) {}
        _ws = null;
        _wsAttempts = 0;
        _wsReconnectTimer?.cancel();
        await _connectWs();
      }
    }
    if (_sseClient == null && !_sseConnecting) await connectSse();
  }

  /// Sends a ping and waits for the sidecar's pong (the sidecar replies to
  /// client {type:'ping'} frames with {type:'pong'}). True = the socket is
  /// genuinely alive end-to-end.
  Future<bool> _probeWs() async {
    final ws = _ws;
    if (ws == null) return false;
    final pong = Completer<bool>();
    late StreamSubscription<RealtimeEvent> sub;
    sub = _events.stream.where((e) => e.type == 'pong').take(1).listen((_) {
      if (!pong.isCompleted) pong.complete(true);
    });
    _sendWs({'type': 'ping'});
    final alive = await pong.future.timeout(_pongTimeout, onTimeout: () => false);
    await sub.cancel();
    return alive;
  }

  /// Joins a conversation room. Recorded immediately so a reconnect
  /// re-joins it; the frame is sent when the socket is up (a pending
  /// connection triggers one).
  void join(int conversationId) {
    if (_disposed) return;
    _joined.add(conversationId);
    _sendWs({'type': 'join', 'conversationId': conversationId});
    if (_ws == null && !_wsConnecting) connectWs();
  }

  void leave(int conversationId) {
    _joined.remove(conversationId);
    _sendWs({'type': 'leave', 'conversationId': conversationId});
  }

  /// Ephemeral typing ping (broadcast to the room minus self; the server
  /// rate-limits floods). The caller owns the once-per-burst/3s-stop logic
  /// (site parity, messages.js).
  void sendTyping(int conversationId, bool isTyping) {
    _sendWs({'type': 'typing', 'conversationId': conversationId, 'isTyping': isTyping});
  }

  void _sendWs(Map<String, dynamic> frame) {
    final ws = _ws;
    if (ws == null) return;
    try {
      ws.add(jsonEncode(frame));
    } catch (_) {}
  }

  /// Opens the SSE stream (header badge events). Same token + budget
  /// rules as the WebSocket; a 401 (dead session) stops retrying — the
  /// REST 401 flow owns that path.
  Future<void> connectSse() async {
    if (_disposed || _sseConnecting) return;
    _sseAttempts = 0;
    await _connectSse();
  }

  Future<void> _connectSse() async {
    if (_disposed || _sseConnecting || _sseClient != null) return;
    _sseConnecting = true;
    try {
      final token = await _token();
      if (token == null) {
        // Same as the WS path: a transient /feed refresh failure must not
        // leave the badge stream dead — retry within the reconnect budget.
        _sseConnecting = false;
        _scheduleSseReconnect();
        return;
      }
      final client = _httpClientFactory();
      final request = await client.getUrl(_eventsUri(token));
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      final response = await request.close();
      _sseConnecting = false;
      if (response.statusCode != HttpStatus.ok) {
        client.close();
        if (response.statusCode == HttpStatus.unauthorized) return;
        _scheduleSseReconnect();
        return;
      }
      _sseClient = client;
      var eventType = '';
      await for (final line in response
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (_disposed) break;
        if (line.startsWith('event:')) {
          eventType = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          final payload = line.substring(5).trim();
          if (eventType.isNotEmpty && payload.isNotEmpty) {
            try {
              final decoded = jsonDecode(payload);
              if (decoded is Map<String, dynamic>) {
                _events.add(RealtimeEvent(type: eventType, data: decoded));
              }
            } catch (_) {}
          }
          eventType = '';
        }
        // ':' lines are heartbeat comments — ignored.
      }
      client.close();
      _sseClient = null;
      _scheduleSseReconnect();
    } on SocketException {
      _sseConnecting = false;
      _scheduleSseReconnect();
    } on HttpException {
      _sseConnecting = false;
      _scheduleSseReconnect();
    } catch (_) {
      _sseConnecting = false;
      _scheduleSseReconnect();
    }
  }

  void _scheduleSseReconnect() {
    if (_disposed) return;
    _sseReconnectTimer?.cancel();
    // EventSource parity: SSE auto-reconnects FOREVER — no attempt budget.
    // The site's badge stream must never die silently for the whole session
    // (Android drops idle sockets; a 5-attempt budget would exhaust in 15s
    // and leave the badge/notification path on the 30s poll only). Backoff
    // grows past the first attempts so a dead network doesn't hammer; an
    // explicit connectSse() (feed foreground resume) resets the backoff.
    // A 401 still stops retrying — a dead session is the REST 401 flow's job.
    final delay = _sseAttempts < 5
        ? _reconnectDelay
        : _reconnectDelay * 10; // prod: 3s -> 30s; tests scale too
    _sseAttempts++;
    _sseReconnectTimer = Timer(delay, _connectSse);
  }

  /// The realtime token: the enclavd_rt cookie the ApiClient captured from
  /// a page render, refreshed via GET /feed when missing or expiring.
  Future<String?> _token() async {
    final rt = _api.sessionCookies
        .where((c) => c.name == 'enclavd_rt')
        .toList();
    if (rt.isNotEmpty && !_tokenExpiring(rt.first.value)) {
      return rt.first.value;
    }
    try {
      // Any logged-in page render re-issues the cookie (header.php →
      // realtime_emit_cookie). /feed is the page the app already fetches
      // for CSRF, so no new surface.
      final resp = await _api.getPage('/feed');
      if (resp.status != 200) return null;
      final fresh = _api.sessionCookies
          .where((c) => c.name == 'enclavd_rt')
          .toList();
      return fresh.isEmpty ? null : fresh.first.value;
    } catch (_) {
      return null;
    }
  }

  /// Token format "<uid>.<unixExpiry>.<hmac>" — the expiry is embedded and
  /// parseable, so the client refreshes before the sidecar starts rejecting.
  bool _tokenExpiring(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return true;
    final expiry = int.tryParse(parts[1]);
    if (expiry == null) return true;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return expiry - now < tokenRefreshSkew.inSeconds;
  }

  Uri _wsUri(String token) {
    final base = Uri.parse(_baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/ws',
      queryParameters: {'token': token},
    );
  }

  Uri _eventsUri(String token) {
    final base = Uri.parse(_baseUrl);
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/events',
      queryParameters: {'token': token},
    );
  }

  /// Closes both transports and stops all timers. Call on logout — the
  /// token dies with the session, so the streams would 401 shortly anyway.
  void dispose() {
    _disposed = true;
    _wsReconnectTimer?.cancel();
    _sseReconnectTimer?.cancel();
    _wsPingTimer?.cancel();
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    _sseClient?.close();
    _sseClient = null;
    _joined.clear();
    _events.close();
  }
}
