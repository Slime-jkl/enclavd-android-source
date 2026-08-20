import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// A single session cookie: name, value and the domain it belongs to.
/// We persist ONLY name/value pairs — flags (HttpOnly/Secure/SameSite) are
/// server-side protections and meaningless to a native client.
class SessionCookie {
  const SessionCookie({required this.name, required this.value});

  final String name;
  final String value;

  Map<String, String> toPrefsJson() => {'n': name, 'v': value};

  factory SessionCookie.fromPrefsJson(Map<String, dynamic> json) =>
      SessionCookie(name: json['n'] as String, value: json['v'] as String);
}

/// Thin storage seam so tests can run without the Flutter plugins layer.
abstract class SessionStore {
  Future<List<SessionCookie>> load();
  Future<void> save(List<SessionCookie> cookies);
  Future<void> clear();
}

/// Production store: SharedPreferences-backed, app-private (mirrors the old
/// WebView wrapper's SharedPreferences session_cookie persistence).
class PrefsSessionStore implements SessionStore {
  static const String _prefsKey = 'enclavd_session_cookies';

  PrefsSessionStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  Future<List<SessionCookie>> load() async {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SessionCookie.fromPrefsJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(List<SessionCookie> cookies) async {
    // Do not persist empty jars — that would overwrite a valid session with
    // nothing on a transient read failure.
    if (cookies.isEmpty) return;
    await _prefs.setString(
        _prefsKey, jsonEncode(cookies.map((c) => c.toPrefsJson()).toList()));
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_prefsKey);
  }
}

/// Result of a raw HTTP exchange: status, headers we care about, body bytes.
class RawResponse {
  const RawResponse({
    required this.status,
    required this.setCookies,
    required this.location,
    required this.body,
  });

  final int status;
  final List<SessionCookie> setCookies;
  final String? location; // Location header (redirect target), if any
  final String body;
}

/// Thrown for non-2xx API responses with the server's message surfaced.
class ApiException implements Exception {
  const ApiException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => 'ApiException($status): $message';
}

/// All api/v1 + legacy auth flows a native client needs.
///
/// Session contract (learned the hard way on the WebView wrapper):
///  - The server agent-binds every login to the User-Agent sent at login.
///  - ANY request with a different UA gets 401 AND destroys the session row.
///  - Therefore EVERY request here goes out with AppConfig.userAgent.
///
/// Cookies: the server uses TWO cookies — `sid` (PHP session: CSRF token,
/// login_token) and `enclavd_sid` (DB-backed session row). Both must be
/// sent together. We capture Set-Cookie on every response and re-send the
/// accumulated jar, persisting it so the session survives app restarts.
class ApiClient {
  ApiClient({
    required this.store,
    HttpClient Function()? httpClientFactory,
    String? apiBaseUrl,
  })  : _httpClientFactory = httpClientFactory ?? _defaultHttpClient,
        _apiBaseUrl = apiBaseUrl ?? AppConfig.apiBaseUrl {
    assert(!_apiBaseUrl.endsWith('/'), 'apiBaseUrl must not end with /');
  }

  final SessionStore store;
  final HttpClient Function() _httpClientFactory;
  final String _apiBaseUrl;

  /// The API root this client talks to (used by services for URL building).
  String get apiBaseUrl => _apiBaseUrl;

  List<SessionCookie> _jar = const [];

  static HttpClient _defaultHttpClient() {
    final client = HttpClient();
    client.userAgent = AppConfig.userAgent;
    client.connectionTimeout = AppConfig.connectTimeout;
    if (AppConfig.allowInsecureTls) {
      client.badCertificateCallback = (cert, host, port) => true;
    }
    return client;
  }

  /// Load the persisted jar into memory. Call once at app start.
  Future<void> restoreSession() async {
    _jar = await store.load();
  }

  List<SessionCookie> get sessionCookies => List.unmodifiable(_jar);

  bool get hasSession => _jar.any((c) => c.name == 'enclavd_sid');

  /// Drops the in-memory jar AND the persisted store. Used on logout and
  /// whenever the server says the session is dead (401). The CSRF token dies
  /// with the PHP session too, so the memoized copy is dropped as well.
  Future<void> clearSession() async {
    _jar = const [];
    _csrfToken = null;
    await store.clear();
  }

  /// HTTP GET of an HTML page (e.g. /login to fetch login_token).
  /// Same-host redirects are followed (browser semantics).
  /// Returns the response with cookies captured.
  Future<RawResponse> getPage(String path, {Map<String, String>? query}) async {
    var current = path;
    var hop = 0;
    while (hop <= AppConfig.maxRedirects) {
      final resp = await _exchange(method: 'GET', path: current, query: query);
      if (resp.status >= 300 && resp.status < 400) {
        final target = _redirectTarget(resp);
        if (target == null) return resp; // cross-host: hand back the 3xx
        current = target;
        query = null;
        hop++;
        continue;
      }
      return resp;
    }
    throw const ApiException('Too many redirects');
  }

  /// HTTP POST of an HTML form (login / register legacy flows).
  ///
  /// Redirects are NOT followed: the auth flows encode their outcome in the
  /// 302 Location (→ /feed = success, back to the form = failure + flash).
  /// Callers read `location` and, on failure, GET the target page to parse
  /// the session flash message. Set-Cookie from the 302 is captured either
  /// way, so the session is established before any follow-up request.
  Future<RawResponse> postForm(
    String path,
    Map<String, String> fields, {
    Map<String, String>? query,
  }) =>
      _exchange(
        method: 'POST',
        path: path,
        query: query,
        formFields: fields,
        followRedirects: false,
      );

  /// HTTP GET against the JSON api/v1 (extensionless path).
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final resp = await _exchange(method: 'GET', path: path, query: query);
    if (resp.status < 200 || resp.status >= 300) {
      throw ApiException(_errorFrom(resp), status: resp.status);
    }
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const ApiException('Invalid response from server');
  }

  /// HTTP POST of a JSON body against the api/v1 (extensionless path).
  ///
  /// api/v1 endpoints read their bodies with api_input() (json_decode) and
  /// gate every state change behind api_csrf_guard(), which accepts the
  /// X-CSRF-Token header. We therefore send:
  ///   Content-Type: application/json
  ///   X-CSRF-Token: <token from the PHP session's rendered meta>
  ///
  /// The CSRF token is memoized per app session (it lives in the PHP session
  /// behind the `sid` cookie, stable until logout). A 403 invalidates the
  /// cache and retries once (the server may have rotated it).
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    // First call in the session: fetch the token before attempting.
    _csrfToken ??= await _fetchCsrfToken();

    final resp = await _postJsonOnce(path, body, _csrfToken);
    if (resp.status == 403) {
      // Token rotated or rejected — refetch and retry exactly once.
      _csrfToken = null;
      final retry = await _postJsonOnce(path, body, await _fetchCsrfToken());
      if (retry.status < 200 || retry.status >= 300) {
        throw ApiException(_errorFrom(retry), status: retry.status);
      }
      return _decodeJson(retry);
    }
    if (resp.status < 200 || resp.status >= 300) {
      throw ApiException(_errorFrom(resp), status: resp.status);
    }
    return _decodeJson(resp);
  }

  Future<RawResponse> _postJsonOnce(
    String path,
    Map<String, dynamic> body,
    String? csrfToken,
  ) =>
      _exchange(
        method: 'POST',
        path: path,
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
          if (csrfToken != null && csrfToken.isNotEmpty)
            AppConfig.hdrCsrf: csrfToken,
        },
        jsonBody: body,
        followRedirects: false,
      );

  Map<String, dynamic> _decodeJson(RawResponse resp) {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const ApiException('Invalid response from server');
  }

  /// Memoized CSRF token (from any page's rendered meta tag). Null until
  /// first fetched; a 403 from postJson clears it and refetches once.
  String? _csrfToken;

  /// Fetches the CSRF token from the rendered meta tag. The PHP session
  /// (sid cookie) holds it; header.php emits it on every page.
  Future<String?> _fetchCsrfToken() async {
    final resp = await getPage('/feed');
    if (resp.status != 200) return null;
    final match = RegExp(
      r'<meta\s+name="csrf-token"\s+content="([^"]+)"',
    ).firstMatch(resp.body);
    _csrfToken = match?.group(1);
    return _csrfToken;
  }

  /// Core exchange: builds the request, sends cookies, captures Set-Cookie.
  ///
  /// `followRedirects` is true only for plain GETs (page fetches, api/v1
  /// reads). Form POSTs pass false so the 302 Location header (the auth
  /// flow's outcome signal) survives to the caller.
  Future<RawResponse> _exchange({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, String>? formFields,
    Map<String, String>? headers,
    Map<String, dynamic>? jsonBody,
    bool followRedirects = true,
    int hop = 0,
  }) async {
    if (hop > AppConfig.maxRedirects) {
      throw const ApiException('Too many redirects');
    }

    final uri = _uriFor(path, query);
    final client = _httpClientFactory();
    try {
      final request = await client.openUrl(method, uri);
      request.followRedirects = false;
      if (_jar.isNotEmpty) {
        request.headers.set(
          AppConfig.hdrCookie,
          _jar.map((c) => '${c.name}=${c.value}').join('; '),
        );
      }
      headers?.forEach(request.headers.set);
      if (formFields != null) {
        request.headers.contentType = ContentType(
            'application', 'x-www-form-urlencoded',
            charset: 'utf-8');
        request.write(const UrlQueryEncoder().encode(formFields));
      }
      if (jsonBody != null) {
        request.write(jsonEncode(jsonBody));
      }

      final response = await request.close().timeout(AppConfig.receiveTimeout);
      // Parse Set-Cookie headers (multiple may be present) — we only keep
      // name=value; flags are server-side protections we don't replay.
      final setCookies = <SessionCookie>[];
      for (final raw
          in response.headers[HttpHeaders.setCookieHeader] ?? <String>[]) {
        final pair = raw.split(';').first;
        final eq = pair.indexOf('=');
        if (eq > 0) {
          setCookies.add(SessionCookie(
            name: pair.substring(0, eq).trim(),
            value: pair.substring(eq + 1).trim(),
          ));
        }
      }
      if (setCookies.isNotEmpty) {
        final changed = _mergeCookies(setCookies);
        if (changed) {
          // Persist immediately so a valid session survives app restarts.
          await store.save(_jar);
        }
      }

      final body = await response.transform(utf8.decoder).join();
      final location = response.headers.value('location');
      final status = response.statusCode;

      return RawResponse(
        status: status,
        setCookies: setCookies,
        location: location,
        body: body,
      );
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } on HttpException catch (e) {
      throw ApiException('HTTP error: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }

  /// Same-host redirect target for a response, or null when it should not
  /// be followed (different host, or the caller wants the 3xx verbatim).
  String? _redirectTarget(RawResponse resp) {
    final location = resp.location;
    if (location == null) return null;
    final base = Uri.parse(_apiBaseUrl);
    final target = location.startsWith('http')
        ? Uri.parse(location)
        : Uri.parse('$base$location');
    if (target.host != base.host) return null;
    return '${target.path}${target.hasQuery ? '?${target.query}' : ''}';
  }

  /// Merges fresh cookies into the jar. Returns true when the jar changed
  /// (new name or changed value) so the caller knows to persist it.
  bool _mergeCookies(List<SessionCookie> fresh) {
    final map = <String, String>{
      for (final c in _jar) c.name: c.value,
      for (final c in fresh) c.name: c.value,
    };
    final next = [
      for (final e in map.entries) SessionCookie(name: e.key, value: e.value)
    ];
    if (next.length != _jar.length) {
      _jar = next;
      return true;
    }
    for (var i = 0; i < next.length; i++) {
      if (next[i].value != _jar[i].value) {
        _jar = next;
        return true;
      }
    }
    return false;
  }

  Uri _uriFor(String path, Map<String, String>? query) {
    final base = Uri.parse(_apiBaseUrl);
    // The path may already carry a query string (redirect targets); split
    // it so we never double-encode.
    var p = path;
    var q = query;
    final question = p.indexOf('?');
    if (question >= 0) {
      final embedded = Uri.splitQueryString(p.substring(question + 1));
      p = p.substring(0, question);
      q = {...embedded, ...?q};
    }
    return Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: p,
      query: q == null ? null : Uri(queryParameters: q).query,
    );
  }

  String _errorFrom(RawResponse resp) {
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } catch (_) {}
    if (resp.body.trim().isNotEmpty && resp.body.trim().length < 200) {
      return resp.body.trim();
    }
    return 'Request failed (${resp.status})';
  }
}

/// Tiny form-url-encoder (keeps the dependency tree at zero).
class UrlQueryEncoder {
  const UrlQueryEncoder();

  String encode(Map<String, String> fields) => fields.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
}
