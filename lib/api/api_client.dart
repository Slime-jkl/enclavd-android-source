import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// A single session cookie: name and value. Flags (HttpOnly/Secure/
/// SameSite) are server-side protections, meaningless to a native client.
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

/// Production store: SharedPreferences-backed, app-private.
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
    // Never persist an empty jar: a transient read failure would wipe a
    // valid session.
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

/// Friendly, non-technical text for ANY caught error - the only way error
/// messages reach a member's eyes. ApiExceptions carry plain-language text
/// already; anything else gets the generic ask, never raw internals.
String friendlyErrorText(Object e) {
  if (e is ApiException && e.message.isNotEmpty) return e.message;
  return 'Something went wrong. Please try again.';
}

/// All api/v1 + legacy auth flows a native client needs.
///
/// The server agent-binds every login to the User-Agent sent at login; ANY
/// request with a different UA gets 401 AND destroys the session row, so
/// every request here goes out with AppConfig.userAgent. Two cookies travel
/// together (`sid` + `enclavd_sid`); Set-Cookie is captured on every
/// response and the jar persisted so sessions survive app restarts.
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

  /// Drops the in-memory jar AND the persisted store (logout / 401). The
  /// CSRF token dies with the PHP session too, so the memo is dropped.
  Future<void> clearSession() async {
    _jar = const [];
    _csrfToken = null;
    await store.clear();
  }

  /// GET of an HTML page (e.g. /login for login_token); follows same-host
  /// redirects (browser semantics).
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

  /// POST of an HTML form (login / register legacy flows). Redirects are
  /// NOT followed: the auth flows encode their outcome in the 302 Location
  /// (to /feed = success, back to the form = failure + flash).
  Future<RawResponse> postForm(
    String path,
    Map<String, String> fields, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) =>
      _exchange(
        method: 'POST',
        path: path,
        query: query,
        formFields: fields,
        headers: headers,
        followRedirects: false,
      );

  /// Memoized CSRF token, parsed from the /feed meta tag on first use;
  /// form POSTs to api/v1 send it as the X-CSRF-Token header.
  Future<String?> fetchCsrfToken() async {
    _csrfToken ??= await _fetchCsrfToken();
    return _csrfToken;
  }

  /// POST of multipart/form-data, the same wire format the site's
  /// post_form.php uses; used by post create.
  Future<RawResponse> postFormMultipart(
    String path,
    Map<String, String> fields, {
    Map<String, String>? headers,
  }) =>
      _exchange(
        method: 'POST',
        path: path,
        formFields: fields,
        multipart: true,
        headers: headers,
        followRedirects: false,
      );

  /// GET against the JSON api/v1 (extensionless path).
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final resp = await _exchange(method: 'GET', path: path, query: query);
    if (resp.status < 200 || resp.status >= 300) {
      throw ApiException(_messageFor(resp), status: resp.status);
    }
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const ApiException('Something went wrong on our side. Please try again.');
  }

  /// POST of a JSON body. api/v1 gates state changes behind
  /// api_csrf_guard(), which accepts the X-CSRF-Token header; the token is
  /// memoized per session (stable until logout), and a 403 refetches and
  /// retries once.
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    // First call in the session: fetch the token before attempting.
    _csrfToken ??= await _fetchCsrfToken();

    final resp = await _postJsonOnce(path, body, _csrfToken);
    if (resp.status == 403) {
      // Token rotated or rejected: refetch and retry exactly once.
      _csrfToken = null;
      final retry = await _postJsonOnce(path, body, await _fetchCsrfToken());
      if (retry.status < 200 || retry.status >= 300) {
        throw ApiException(_messageFor(retry), status: retry.status);
      }
      return _decodeJson(retry);
    }
    if (resp.status < 200 || resp.status >= 300) {
      throw ApiException(_messageFor(resp), status: resp.status);
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
    throw const ApiException('Something went wrong on our side. Please try again.');
  }

  /// Friendly message for a non-2xx response: 4xx bodies carry real
  /// business messages; 5xx is our side breaking - never surface raw
  /// server text for those.
  String _messageFor(RawResponse resp) =>
      resp.status >= 500
          ? 'Something went wrong on our side. Please try again.'
          : _errorFrom(resp);

  /// POST returning decoded JSON regardless of status, so callers can read
  /// structured error payloads (e.g. register's {error, fields} map). Only
  /// transport failures throw; non-JSON bodies (e.g. an undeployed
  /// endpoint's 404 HTML) come back as {'error': 'Request failed (NNN)'}.
  Future<Map<String, dynamic>> postJsonRelaxed(
    String path,
    Map<String, dynamic> body,
  ) async {
    _csrfToken ??= await _fetchCsrfToken();
    var resp = await _postJsonOnce(path, body, _csrfToken);
    if (resp.status == 403) {
      // Token rotated or rejected: refetch and retry exactly once.
      _csrfToken = null;
      resp = await _postJsonOnce(path, body, await _fetchCsrfToken());
    }
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {'error': 'Request failed (${resp.status})'};
  }

  /// Memoized CSRF token (from any page's rendered meta tag). Null until
  /// first fetched; a 403 from postJson clears it and refetches once.
  String? _csrfToken;

  /// Parses the CSRF token from a page's meta tag (header.php emits it on
  /// every page).
  Future<String?> _fetchCsrfToken() async {
    final resp = await getPage('/feed');
    if (resp.status != 200) return null;
    final match = RegExp(
      r'<meta\s+name="csrf-token"\s+content="([^"]+)"',
    ).firstMatch(resp.body);
    _csrfToken = match?.group(1);
    return _csrfToken;
  }

  /// Core exchange: builds the request, sends the jar, captures Set-Cookie.
  /// Redirects are followed only for GETs; form POSTs pass false so the
  /// 302 Location header survives to the caller.
  Future<RawResponse> _exchange({
    required String method,
    required String path,
    Map<String, String>? query,
    Map<String, String>? formFields,
    Map<String, String>? headers,
    Map<String, dynamic>? jsonBody,
    bool multipart = false,
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
        if (multipart) {
          final boundary = 'enclavd_${DateTime.now().microsecondsSinceEpoch}';
          request.headers.contentType = ContentType(
            'multipart',
            'form-data',
            parameters: {'boundary': boundary},
          );
          final body = _buildMultipartBody(formFields, boundary);
          request.contentLength = body.length;
          request.add(body);
        } else {
          request.headers.contentType = ContentType(
              'application', 'x-www-form-urlencoded',
              charset: 'utf-8');
          // Explicit Content-Length: without it dart:io sends chunked,
          // and PHP-FPM does not deliver large chunked bodies intact -
          // json_decode/api_input() sees an empty body and the endpoint
          // answers "Unknown action". (Reproduced Aug 2026: 16MB chunked
          // -> 400; same body with Content-Length -> 200.)
          final encoded = const UrlQueryEncoder().encode(formFields);
          request.contentLength = utf8.encode(encoded).length;
          request.write(encoded);
        }
      }
      if (jsonBody != null) {
        final encoded = jsonEncode(jsonBody);
        request.contentLength = utf8.encode(encoded).length;
        request.write(encoded);
      }

      final response = await request.close().timeout(AppConfig.receiveTimeout);
      // Capture Set-Cookie (multiple may be present); keep only name=value.
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
    } on SocketException {
      // Friendly, non-technical: raw socket messages leak internals.
      throw const ApiException('No network. Check your connection and try again.');
    } on HttpException {
      throw const ApiException('No network. Check your connection and try again.');
    } on TimeoutException {
      throw const ApiException('No network. Check your connection and try again.');
    } finally {
      client.close(force: true);
    }
  }

  /// Same-host redirect target for a response, or null when it should not
  /// be followed. Legacy endpoints redirect with RELATIVE Locations
  /// (header('Location: login') - no leading slash); without normalization
  /// `$base$location` would parse as a different host and never be
  /// followed.
  String? _redirectTarget(RawResponse resp) {
    final location = resp.location;
    if (location == null) return null;
    final base = Uri.parse(_apiBaseUrl);
    final target = location.startsWith('http')
        ? Uri.parse(location)
        : Uri.parse('$base${location.startsWith('/') ? location : '/$location'}');
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

  /// RFC 2046 multipart body, text-only parts: the image travels as base64
  /// inside `image_data`, exactly like the site's ied output.
  List<int> _buildMultipartBody(Map<String, String> fields, String boundary) {
    final buf = BytesBuilder();
    void write(String s) => buf.add(utf8.encode(s));
    fields.forEach((key, value) {
      write('--$boundary\r\n');
      write('Content-Disposition: form-data; name="$key"\r\n\r\n');
      write(value);
      write('\r\n');
    });
    write('--$boundary--\r\n');
    return buf.takeBytes();
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
