import 'package:flutter/foundation.dart';

import '../../api/api_client.dart';

/// Registers this device's push token with the server
/// (POST /api/v1/push/register — the web-side contract, deployed
/// separately from the app).
///
/// Deliberately fire-and-forget: every failure is swallowed and retried on
/// the next app start or token refresh. The endpoint may not be deployed
/// yet (404), the session may be missing (401 — cold start before login),
/// or the network flaky — none of that should ever break the app. The
/// polling fallback keeps notifications flowing until the server side is
/// live.
class PushRegistrationService {
  PushRegistrationService(this._clientFactory);

  /// Late-bound to the CURRENT app container at call time (the
  /// singleton-captured-stale-ApiClient lesson: a client from the first
  /// cold-start container has an empty jar and would 401 every
  /// registration until the next login).
  final Future<ApiClient> Function() _clientFactory;

  /// Upserts the token. [token] is the FCM registration token OR the
  /// Unified Push endpoint URL — the server treats it as the device's
  /// push address for [transport] ('fcm' | 'unifiedpush').
  Future<void> register({
    required String transport,
    required String token,
  }) async {
    try {
      final api = await _clientFactory();
      if (!api.hasSession) return; // not logged in yet — next start retries
      await api.postJson('/api/v1/push/register', {
        'transport': transport,
        'token': token,
        'platform': 'android',
      });
      debugPrint('push: registered $transport token');
    } catch (e) {
      debugPrint('push: register failed (retry next start): $e');
    }
  }

  /// Drops the token. Silent on failure — the server prunes stale tokens
  /// itself; this is a best-effort courtesy (a logged-out client cannot
  /// authenticate the call anyway).
  Future<void> unregister({
    required String transport,
    required String token,
  }) async {
    try {
      final api = await _clientFactory();
      if (!api.hasSession) return;
      await api.postJson('/api/v1/push/unregister', {
        'transport': transport,
        'token': token,
      });
    } catch (e) {
      debugPrint('push: unregister failed (ignored): $e');
    }
  }
}
