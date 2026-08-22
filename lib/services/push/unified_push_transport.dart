import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:unifiedpush/unifiedpush.dart';

import 'push_registration_service.dart';
import 'push_transport.dart';

/// Unified Push transport — the F-Droid-friendly channel (and the fallback
/// on Play builds without Google Play services).
///
/// Works through a DISTRIBUTOR app (ntfy, Conversations, NextPush, …)
/// installed by the user. When no distributor exists, [init] returns false
/// and the manager falls back to the 15-minute polling — the settings row
/// hints at installing a distributor for instant alerts.
///
/// Server contract: the distributor hands the app a gateway ENDPOINT URL;
/// the app registers that URL (as `token`) with the server, and the
/// server POSTs a small payload to it whenever there is new data. The
/// payload is ignored by the app (any message → [onSync]); the simplest
/// server payload is a plain JSON body. Encryption via
/// [PushEndpoint.pubKeySet] (RFC 8291 web-push) is optional and only
/// needed for distributors that reject unencrypted messages.
class UnifiedPushTransport implements PushTransport {
  UnifiedPushTransport({required this.registration, required this.onSync});

  static const String transportId = 'unifiedpush';

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
      // distributor changes it — keep the server's copy fresh.
      onNewEndpoint: (endpoint, instance) => unawaited(
        registration.register(transport: transportId, token: endpoint.url),
      ),
      onRegistrationFailed: (reason, instance) =>
          debugPrint('push: UP registration failed: $reason'),
      onUnregistered: (instance) => unawaited(
        registration.unregister(transport: transportId, token: ''),
      ),
      onMessage: (message, instance) => unawaited(_handleMessage(message, onSync)),
      onTempUnavailable: (instance) =>
          debugPrint('push: UP backend temporarily unavailable'),
    );
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
      // No distributor saved yet — adopt the device's default distributor
      // if one exists; otherwise auto-pick the first installed one (no
      // picker UI in v1; the settings row hints at installing one).
      final adopted = await UnifiedPush.tryUseCurrentOrDefaultDistributor();
      if (!adopted) {
        final distributors = await UnifiedPush.getDistributors();
        if (distributors.isEmpty) {
          debugPrint('push: UP unavailable — no distributor on this device');
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
    // No-op: the endpoint is delivered asynchronously via onNewEndpoint
    // (on this start and every future start) — there is no synchronous
    // getter for it in the plugin API.
  }

  /// The --unifiedpush-bg entrypoint (main() sees the arg and calls this
  /// instead of runApp): UnifiedPush woke a headless isolate for an
  /// incoming message. Bind the same callbacks and let the plugin keep
  /// the engine alive. There is no UI, and registration is pointless here
  /// (the endpoint re-delivers on the next normal start) — the throwing
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
