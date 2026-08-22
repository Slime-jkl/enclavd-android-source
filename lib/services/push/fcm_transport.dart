import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_registration_service.dart';
import 'push_transport.dart';

/// FCM transport — the Google Play builds' channel
/// (AppConfig.enableFcm; F-Droid never constructs this class).
///
/// Requires the Firebase project's google-services.json in
/// android/app/ (processed by the google-services gradle plugin, which the
/// build applies only when the file exists). Without it — or without
/// Google Play services on the device — [init] throws and the manager
/// falls through to Unified Push / polling.
///
/// Payload contract: the server sends DATA-only messages (no notification
/// block — the app renders its own notifications through
/// flutter_local_notifications, so the drawer-reply and tap flows stay
/// native). The data payload itself is ignored: any FCM message means
/// "something changed", and [onSync] re-checks both notification sources.
/// The server only needs the registration token.
class FcmTransport implements PushTransport {
  FcmTransport({required this.registration, required this.onSync});

  static const String transportId = 'fcm';

  final PushRegistrationService registration;
  final Future<void> Function() onSync;

  String? _token;
  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<String>? _tokenSub;

  @override
  String get id => transportId;

  @override
  String get label => 'FCM push';

  /// Registers the killed-process callback. firebase_messaging maps this
  /// entrypoint before the engine starts; called from main(). The handler
  /// itself is a plain top-level function the plugin invokes in a fresh
  /// headless isolate when a data message arrives while the app is dead.
  static void bindBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  @override
  Future<bool> init() async {
    // No-arg initializeApp() uses the NATIVE default options (the
    // google-services.json processed by the gradle plugin) — which is
    // exactly what the killed-process path needs: the native
    // FirebaseInitProvider must be able to init the default app before
    // any Dart runs. Throws when the file is absent or the device has no
    // Google Play services.
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) {
      throw StateError('FCM token unavailable');
    }
    _token = token;
    // Foreground messages: the live SSE path is primary; this is the
    // backup when a socket is down. Shared dedupe makes it harmless.
    // (v16 API note: onMessage is a STATIC getter; onTokenRefresh below
    // is an INSTANCE getter — asymmetric, don't mix them up.)
    _messageSub = FirebaseMessaging.onMessage.listen((_) => unawaited(onSync()));
    _tokenSub = messaging.onTokenRefresh.listen((String refreshed) {
      _token = refreshed;
      unawaited(
        registration.register(transport: transportId, token: refreshed),
      );
    });
    await registration.register(transport: transportId, token: token);
    return true;
  }

  @override
  Future<void> registerToken() async {
    final token = _token;
    if (token == null) return;
    await registration.register(transport: transportId, token: token);
  }

  /// Tears the transport down (logout path): stop listening and drop the
  /// token server-side. Best-effort — the server prunes stale tokens too.
  Future<void> dispose() async {
    await _messageSub?.cancel();
    _messageSub = null;
    await _tokenSub?.cancel();
    _tokenSub = null;
    final token = _token;
    _token = null;
    if (token != null) {
      await registration.unregister(transport: transportId, token: token);
    }
  }
}

/// firebase_messaging's killed-process entrypoint: a data message woke a
/// headless isolate (no singletons, no UI). Run the worker-style full
/// pipeline — fresh session from prefs, fresh plugin, shared dedupe.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await syncFromPush();
  } catch (e) {
    // The polling fallback still runs; never let a push crash the isolate.
    debugPrint('push: FCM background sync failed: $e');
  }
}
