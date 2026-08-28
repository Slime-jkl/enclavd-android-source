import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';

import 'push_registration_service.dart';
import 'push_transport.dart';

/// Unified Push transport - the F-Droid-friendly channel (and the fallback
/// on Play builds without Google Play services). Works through a
/// DISTRIBUTOR app installed by the user; with none, [init] returns false
/// and the manager falls back to 15-minute polling. Server contract: the
/// distributor hands the app a gateway ENDPOINT URL, the app registers it
/// (as `token`), and the server POSTs a small payload on new data - any
/// message -> [onSync]. Encryption via [PushEndpoint.pubKeySet] (RFC 8291)
/// is optional, only for distributors that reject unencrypted messages.
class UnifiedPushTransport implements PushTransport {
  UnifiedPushTransport({required this.registration, required this.onSync});

  static const String transportId = 'unifiedpush';

  /// The distributor only delivers the endpoint asynchronously
  /// (onNewEndpoint); persisting it means a registration skipped on a
  /// pre-login cold start can be replayed later by [registerToken].
  static const String endpointPrefsKey = 'push_up_endpoint';

  final PushRegistrationService registration;
  final Future<void> Function() onSync;

  @override
  String get id => transportId;

  @override
  String get label => 'Unified Push';

  /// Binds the event callbacks and reports whether a distributor is
  /// already registered. Shared by the normal init path and the
  /// --unifiedpush-bg headless entrypoint ([runBackground]).
  static Future<bool> _bindCallbacks({
    required PushRegistrationService registration,
    required Future<void> Function() onSync,
  }) {
    return UnifiedPush.initialize(
      // The endpoint (re)delivers on every process start and whenever the
      // distributor changes it: persist + keep the server's copy fresh.
      onNewEndpoint: (endpoint, instance) =>
          unawaited(_persistAndRegisterEndpoint(endpoint.url, registration)),
      onRegistrationFailed: (reason, instance) =>
          debugPrint('push: UP registration failed: $reason'),
      onUnregistered: (instance) => unawaited(_clearEndpoint()),
      onMessage: (message, instance) => unawaited(_handleMessage(message, onSync)),
      onTempUnavailable: (instance) =>
          debugPrint('push: UP backend temporarily unavailable'),
    );
  }

  /// Persists the endpoint, then registers it with the server. The persist
  /// step lets a registration skipped for lack of a session (cold start ->
  /// login screen -> onNewEndpoint fired before login) be replayed later
  /// by [registerToken].
  static Future<void> _persistAndRegisterEndpoint(
    String endpoint,
    PushRegistrationService registration,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(endpointPrefsKey, endpoint);
    await registration.register(transport: transportId, token: endpoint);
  }

  /// Forgets the stored endpoint (distributor dropped the app); the server
  /// row is left to the sender's own pruning (410/404).
  static Future<void> _clearEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(endpointPrefsKey);
  }

  static Future<void> _handleMessage(
    PushMessage message,
    Future<void> Function() onSync,
  ) async {
    try {
      debugPrint('push: UP message: ${utf8.decode(message.content)}');
    } catch (_) {
      debugPrint('push: UP message (non-UTF8 bytes)');
    }
    await onSync();
  }

  @override
  Future<bool> init() async {
    var hasDistributor =
        await _bindCallbacks(registration: registration, onSync: onSync);
    if (!hasDistributor) {
      // No distributor saved: adopt the device's default, else auto-pick
      // the first installed one (no picker UI in v1).
      final adopted = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
      if (!adopted) {
        final distributors = await UnifiedPush.getDistributors();
        if (distributors.isEmpty) {
          debugPrint('push: UP unavailable - no distributor on this device');
          return false;
        }
        await UnifiedPush.saveDistributor(distributors.first);
      }
    }
    // The plugin docs require register() at every app startup with the
    // same instance; the fresh endpoint arrives via onNewEndpoint.
    await UnifiedPush.register();
    debugPrint('push: UP active');
    return true;
  }

  @override
  Future<void> registerToken() async {
    // Replay the persisted endpoint: the distributor delivers it
    // asynchronously (onNewEndpoint), so the pre-login cold start may
    // have skipped registration. No stored endpoint -> nothing to do.
    final prefs = await SharedPreferences.getInstance();
    final endpoint = prefs.getString(endpointPrefsKey);
    if (endpoint == null || endpoint.isEmpty) return;
    await registration.register(transport: transportId, token: endpoint);
  }

  /// The --unifiedpush-bg entrypoint (main() sees the arg and calls this
  /// instead of runApp): UnifiedPush woke a headless isolate for an
  /// incoming message. Bind the same callbacks and let the plugin keep
  /// the engine alive. No UI, and registration is pointless here (the
  /// endpoint re-delivers on the next normal start) - the throwing
  /// client factory makes any register attempt a silent no-op.
  static Future<void> runBackground() async {
    await _bindCallbacks(
      registration: PushRegistrationService(
        () async => throw StateError('background isolate'),
      ),
      onSync: syncFromPush,
    );
  }
}
