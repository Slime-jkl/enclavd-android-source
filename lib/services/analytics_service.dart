import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

/// Client for the app's own self-hosted Plausible instance
/// (https://enclavd.com:2000, the same origin the site's header script
/// posts to).
///
/// Wire format read off the site's script.js: POST /api/event with
/// `Content-Type: text/plain` and a JSON body {n, u, d, r, p} - the SAME
/// shape the site sends, so app pageviews land in the same dashboard as
/// web visits. Time on page needs no duration payload: Plausible computes
/// it server-side from the gap between consecutive pageviews.
///
/// Two API requirements: the User-Agent must LOOK like a browser (bot
/// filter) - requests carry the PINNED Chrome/124 string the old WebView
/// wrapper always sent, keeping visitor identity stable; and the socket
/// IP must be the client's own, which it is (the app connects straight
/// to enclavd.com). Fire-and-forget by design: every failure is a silent
/// no-op. Analytics must never break the UI.
class AnalyticsService {
  AnalyticsService({
    required this.endpoint,
    required this.domain,
    required this.userAgent,
  });

  /// App-wide instance set by AppServices.create; null when analytics is
  /// disabled (debug builds, dev flavor), so callers use the null-safe
  /// `AnalyticsService.instance?.pageview('/path')`.
  static AnalyticsService? instance;

  /// Full events API URL (default: the site's proxied Plausible).
  final String endpoint;

  /// The Plausible site domain the events belong to (the site's
  /// data-domain attribute).
  final String domain;

  /// Browser-like User-Agent header (Plausible drops non-browser UAs).
  final String userAgent;

  String? _lastPath;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  /// Skips a re-fired pageview for the same path within this window
  /// (double announces, tab re-taps).
  static const Duration debounceWindow = Duration(seconds: 2);

  /// Records a pageview for a site-style path (e.g. '/feed', '/profile',
  /// '/messages'); must start with '/'.
  void pageview(String path) {
    final now = DateTime.now();
    if (path == _lastPath && now.difference(_lastSent) < debounceWindow) {
      return;
    }
    _lastPath = path;
    _lastSent = now;
    unawaited(_send({
      'n': 'pageview',
      'u': 'https://$domain$path',
      'd': domain,
      'r': null,
    }));
  }

  /// Records a custom event, like the script's `plausible('name')`, e.g.
  /// event('Signup'); custom props need the props feature enabled.
  void event(String name, {Map<String, dynamic>? props}) {
    unawaited(_send({
      'n': name,
      'u': 'https://$domain/',
      'd': domain,
      'r': null,
      if (props != null && props.isNotEmpty) 'p': props,
    }));
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    HttpClient? client;
    try {
      client = HttpClient();
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.contentType =
          ContentType('text', 'plain', charset: 'utf-8');
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final body = utf8.encode(jsonEncode(payload));
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close();
      await response.drain<void>();
    } catch (_) {
      // Offline, server down, malformed response: never surface.
    } finally {
      client?.close(force: true);
    }
  }
}

/// Fires a pageview on named-route pushes and pops (the site's
/// pushState/popstate equivalent). Routes without a settings.name (direct
/// MaterialPageRoute pushes) are tracked by the screens' own initState
/// calls.
class AnalyticsRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _track(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _track(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Returning to the previous screen is a pageview for THAT screen
    // (the site's popstate -> pageview).
    _track(previousRoute);
  }

  void _track(Route<dynamic>? route) {
    if (route is! PageRoute) return; // dialogs, bottom sheets
    final name = route.settings.name;
    if (name == null || name.isEmpty) return;
    AnalyticsService.instance?.pageview(name);
  }
}

/// One-line screen tracking helper: `trackScreen('/profile')` in a
/// screen's initState. Null-safe - no-op when analytics is off.
void trackScreen(String path) => AnalyticsService.instance?.pageview(path);
