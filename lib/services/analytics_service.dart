import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

/// Analytics client for the app's own self-hosted Plausible instance
/// (https://enclavd.com:2000 — proxied by the web server, the same origin
/// the site's header script posts to).
///
/// The wire format below is read straight off the site's script.js: a POST
/// to /api/event with `Content-Type: text/plain` and a JSON body of
/// {n: name, u: url, d: domain, r: referrer, p: props}. Sending the SAME
/// shape from the app puts app pageviews into the SAME dashboard as the
/// website's — screen names arrive as site-style paths (/feed, /profile,
/// /messages...) so "Top Pages" and time-on-page behave exactly like web
/// visits. Time on page needs no duration payload: Plausible computes it
/// server-side from the gap between consecutive pageviews, so the app only
/// has to fire a pageview when the user lands on a screen.
///
/// Two requirements Plausible enforces on the API:
///  1. The User-Agent must LOOK like a browser or the event is silently
///     dropped (bot filter). The app's own UA (EnclavdNative/1.0) would be
///     discarded, so analytics requests carry the app's PINNED Chrome/124
///     string — the exact UA the old WebView wrapper always sent, so the
///     same phone keeps the same visitor identity across app versions.
///  2. The request must carry the client's IP at the socket level for
///     country/visit counting. The app connects straight to enclavd.com,
///     so the socket IP is the phone's own — no header spoofing needed.
///
/// Fire-and-forget by design: every failure is a silent no-op (offline,
/// server down, test environments). Analytics must never break the UI.
class AnalyticsService {
  AnalyticsService({
    required this.endpoint,
    required this.domain,
    required this.userAgent,
  });

  /// The app-wide instance, set by [AppServices.create]. Null when
  /// analytics is disabled (debug builds, the dev flavor) — callers use
  /// `AnalyticsService.instance?.pageview('/path')`, a null-safe no-op.
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

  /// Skips a pageview for the SAME path re-fired within this window —
  /// a screen can be announced from two places (route observer + the
  /// screen's own initState) and tab re-taps must not double-count.
  static const Duration debounceWindow = Duration(seconds: 2);

  /// Records a pageview for a site-style path (e.g. '/feed', '/profile',
  /// '/messages'). The path must start with '/' and becomes the "page"
  /// the user is on.
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

  /// Records a custom event (the script's `plausible('name')`): e.g.
  /// event('Signup') or event('Post created', props: {'has_image': true}).
  /// Custom properties require the site's Plausible to have the props
  /// feature enabled (it does for the site's own script usage).
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
      // Offline, server down, malformed response — never surface.
    } finally {
      client?.close(force: true);
    }
  }
}

/// Fires a pageview whenever a NAMED route is pushed (the site's script
/// fires on pushState/popstate — this is the same behavior for the
/// navigator). Routes without a settings.name (the app's direct
/// MaterialPageRoute pushes) are tracked by the screens' own initState
/// calls; this observer covers the named routes (/login, /register, /feed,
/// /ban, /maintenance, /verify_email) plus any future named navigation.
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
    // (the site's popstate → pageview).
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
/// screen's initState. Null-safe — no-op when analytics is off.
void trackScreen(String path) => AnalyticsService.instance?.pageview(path);
