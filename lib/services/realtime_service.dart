import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../config/app_config.dart';

/// One parsed realtime frame (WebSocket or SSE); camelCase on WS frames,
/// snake_case in SSE payloads.
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

/// WebSocket (chat) + SSE (badge) client for the Go sidecar. REST stays
/// the source of truth and the poll fallback. Reconnects forever while the
/// app is alive (Android drops idle sockets); backoff grows 3s to 30s.
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

  /// Pong wait before declaring the socket dead; tests pass a tiny value.
  final Duration _pongTimeout;

  /// Backoff knee: after this many failures the wait grows to 10x. Not a
  /// hard cap; the WS reconnects indefinitely while the app is alive.
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

  /// True while the SSE stream is open, false when it ended or errored.
  final _sseStatus = StreamController<bool>.broadcast();
  Stream<bool> get sseStatus => _sseStatus.stream;

  void _emitSseStatus(bool connected) {
    if (!_sseStatus.isClosed) _sseStatus.add(connected);
  }

  WebSocket? _ws;
  bool _wsConnecting = false;
  int _wsAttempts = 0;
  Timer? _wsReconnectTimer;
  Timer? _wsPingTimer;

  /// Rooms to re-join on every (re)connect so a reconnect never leaves a
  /// screen deaf.
  final Set<int> _joined = {};

  bool _sseConnecting = false;
  int _sseAttempts = 0;
  Timer? _sseReconnectTimer;
  HttpClient? _sseClient;
  StreamSubscription<String>? _sseSub; // the active SSE line stream
  String _sseEventType = ''; // 'event:' -> 'data:' pairing across lines

  bool _disposed = false;

  bool get isWsConnected => _ws != null;

  /// True while the SSE stream is open; the badge poll gates on this.
  bool get isSseConnected => _sseClient != null;

  bool get isConnecting => _wsConnecting || _sseConnecting;

  /// Opens the WebSocket; an explicit call resets the reconnect budget.
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
        // Token fetch failed; retry like any other failure.
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
      // Keep backing off after a post-handshake drop; the reset happens
      // in connectWs()/onForeground(). Re-join every tracked room.
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
      // Malformed frame - drop; the next poll reconciles any gap.
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
    // Reconnect forever while the app is alive; Android drops idle
    // sockets. Backoff grows so a dead network doesn't hammer;
    // connectWs()/onForeground() reset it.
    final delay = _wsAttempts < maxReconnectAttempts
        ? _reconnectDelay
        : _reconnectDelay * 10; // prod: 3s -> 30s; tests scale too
    _wsAttempts++;
    _wsReconnectTimer = Timer(delay, _connectWs);
  }

  /// Foreground resume: reconnect the socket (probing a zombie half-open
  /// with a ping) and force a fresh SSE stream.
  Future<void> onForeground() async {
    if (_disposed) return;
    _wsReconnectTimer?.cancel();
    if (_ws == null) {
      if (!_wsConnecting) await connectWs();
    } else {
      final alive = await _probeWs();
      if (!alive && !_disposed && _ws != null) {
        // Zombie socket: normal close path, then reconnect fresh.
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
    // SSE is one-way: nothing to probe, so a zombie reads as connected
    // and delivers nothing forever. Tear down and reconnect fresh.
    debugPrint('RT: onForeground - forcing fresh SSE stream');
    _forceSseReconnect();
    await connectSse();
  }

  /// Pings the socket and waits for the sidecar's pong; true = genuinely
  /// alive end-to-end.
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

  /// Joins a conversation room; recorded so reconnects re-join it.
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

  /// Ephemeral typing ping; the caller owns the burst/stop logic.
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

  /// Opens the SSE stream; a 401 (dead session) stops retrying.
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
        // Transient /feed failure must not kill the badge stream; retry.
        _sseConnecting = false;
        _scheduleSseReconnect();
        return;
      }
      debugPrint('RT: sse connecting (token ok)');
      final client = _httpClientFactory();
      final request = await client.getUrl(_eventsUri(token));
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      final response = await request.close();
      _sseConnecting = false;
      if (response.statusCode != HttpStatus.ok) {
        client.close();
        debugPrint('RT: sse status ${response.statusCode}');
        if (response.statusCode == HttpStatus.unauthorized) {
          debugPrint('RT: sse 401 - session dead, stop retrying');
          return;
        }
        _scheduleSseReconnect();
        return;
      }
      _sseClient = client;
      _emitSseStatus(true);
      debugPrint('RT: sse connected');
      _sseEventType = '';
      // Explicit subscription, not await-for: the force-reconnect path
      // must be able to cancel the in-flight stream.
      _sseSub = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        _onSseLine,
        onError: (_) => _sseStreamEnded(client),
        onDone: () => _sseStreamEnded(client),
      );
    } on SocketException {
      _sseConnecting = false;
      _sseClient = null;
      _emitSseStatus(false);
      debugPrint('RT: sse socket error - reconnect');
      _scheduleSseReconnect();
    } on HttpException {
      _sseConnecting = false;
      _sseClient = null;
      _emitSseStatus(false);
      debugPrint('RT: sse http error - reconnect');
      _scheduleSseReconnect();
    } catch (_) {
      _sseConnecting = false;
      _sseClient = null;
      _emitSseStatus(false);
      _scheduleSseReconnect();
    }
  }

  void _onSseLine(String line) {
    if (_disposed) return;
    if (line.startsWith('event:')) {
      _sseEventType = line.substring(6).trim();
    } else if (line.startsWith('data:')) {
      final payload = line.substring(5).trim();
      if (_sseEventType.isNotEmpty && payload.isNotEmpty) {
        try {
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) {
            debugPrint('RT: sse event $_sseEventType');
            _events.add(RealtimeEvent(type: _sseEventType, data: decoded));
          }
        } catch (_) {}
      }
      _sseEventType = '';
    }
    // ':' lines are heartbeat comments; ignored.
  }

  /// Cleans up only when this stream is still the current one, so a stale
  /// stream can't clobber the new connection's state.
  void _sseStreamEnded(HttpClient client) {
    _sseSub?.cancel();
    _sseSub = null;
    client.close();
    if (identical(_sseClient, client)) {
      _sseClient = null;
      _emitSseStatus(false);
      debugPrint('RT: sse stream ended - reconnect');
      _scheduleSseReconnect();
    }
  }

  /// Tears the current SSE stream down so a fresh one can be opened.
  void _forceSseReconnect() {
    _sseReconnectTimer?.cancel();
    _sseConnecting = false;
    _sseSub?.cancel();
    _sseSub = null;
    final client = _sseClient;
    if (client != null) {
      _sseClient = null;
      client.close(force: true);
      _emitSseStatus(false);
    }
  }

  void _scheduleSseReconnect() {
    if (_disposed) return;
    _sseReconnectTimer?.cancel();
    // EventSource parity: SSE auto-reconnects forever; a dead network
    // backs off instead of hammering. A 401 still stops retrying - the
    // REST 401 flow owns that path.
    final delay = _sseAttempts < 5
        ? _reconnectDelay
        : _reconnectDelay * 10; // prod: 3s -> 30s; tests scale too
    _sseAttempts++;
    debugPrint('RT: sse reconnect in ${delay.inSeconds}s (attempt $_sseAttempts)');
    _sseReconnectTimer = Timer(delay, _connectSse);
  }

  /// The enclavd_rt cookie from the jar, refreshed via GET /feed when
  /// missing or expiring.
  Future<String?> _token() async {
    final rt = _api.sessionCookies
        .where((c) => c.name == 'enclavd_rt')
        .toList();
    if (rt.isNotEmpty && !_tokenExpiring(rt.first.value)) {
      return rt.first.value;
    }
    try {
      // Any logged-in page render re-issues the cookie; /feed is already
      // fetched for CSRF, so no new surface.
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

  /// Token is "<uid>.<unixExpiry>.<hmac>", so the client can refresh
  /// before the sidecar starts rejecting.
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

  /// Closes both transports and stops all timers; call on logout.
  void dispose() {
    _disposed = true;
    _wsReconnectTimer?.cancel();
    _sseReconnectTimer?.cancel();
    _wsPingTimer?.cancel();
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    _sseSub?.cancel();
    _sseSub = null;
    _sseClient?.close(force: true);
    _sseClient = null;
    _joined.clear();
    _events.close();
    _sseStatus.close();
  }
}
