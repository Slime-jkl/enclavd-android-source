import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../config/app_config.dart';
import 'fcm_transport.dart';
import '../message_notifications.dart';
import '../notification_worker.dart';
import 'push_registration_service.dart';
import '../social_notifications.dart';
import 'unified_push_transport.dart';

/// A background push transport: something that can wake the app's process
/// (or a headless isolate of it) when the server has new data — instead of
/// waiting up to 15 minutes for the WorkManager poll.
///
/// A transport's only job is to turn an incoming push into a call to
/// [syncFromPush]. It never fetches or renders anything itself: the
/// existing two-path notification pipeline is reused verbatim (live
/// SSE/WS handlers in the main isolate, worker-style full run in
/// background isolates), including the cross-path NotifiedTracker dedupe —
/// so a push can never duplicate something the live path or the 15-minute
/// poll already showed.
abstract class PushTransport {
  /// Short transport id ('fcm' | 'unifiedpush') — sent to the server as
  /// the registration transport.
  String get id;

  /// Human label for the settings status row.
  String get label;

  /// Bring the transport up: bind handlers, obtain a token/endpoint and
  /// register it with the server. Returns true when the transport is
  /// ACTIVE on this build/device. Throws when it is unusable (missing
  /// google-services.json, no Google Play services, no Unified Push
  /// distributor) — the manager catches and falls through.
  Future<bool> init();

  /// (Re)send the current token/endpoint to the server. Called on every
  /// app start and after a fresh login — the session may not have existed
  /// when [init] ran.
  Future<void> registerToken();
}

/// Resolves and owns the best push transport for the current build and
/// device, and turns every incoming push into a notification sync.
///
/// Resolution order (runtime, per build):
///   play/dev: FCM → Unified Push → 15-minute polling fallback
///   fdroid:   Unified Push → 15-minute polling fallback — FCM is never
///             even attempted (that build must not touch Google Play
///             services).
///
/// The 15-minute WorkManager poll is ALWAYS registered independently (it
/// is the safety net); the transports only make delivery faster when the
/// app is killed. The shared dedupe makes the overlap harmless.
class PushManager {
  PushManager._();

  static PushManager? instance;

  /// The active transport, or null when only the polling fallback is
  /// available on this device.
  PushTransport? _active;
  PushTransport? get active => _active;

  static const String fallbackLabel = '15-minute background checks';

  /// Prefs flag the native side reads (FlutterSharedPreferences, key
  /// prefixed "flutter.") to skip the keep-alive foreground service when a
  /// push transport is active — background delivery is the push service's
  /// job then, and the persistent "Live updates active" notice is noise.
  /// Written by [ensureResolved]; defaults false (fallback machinery on).
  static const String pushActivePrefsKey = 'push_transport_active';

  /// Binds handlers that must exist BEFORE the engine starts — FCM's
  /// killed-process callback (firebase_messaging requires the registration
  /// early). No-op on F-Droid builds (they never touch FCM) and when the
  /// whole notification feature is compiled out.
  static void bindBackgroundHandlers() {
    if (!AppConfig.enableNotifications || !AppConfig.enableFcm) return;
    FcmTransport.bindBackgroundHandler();
  }

  /// Resolves the transport once (idempotent), or — when already resolved
  /// (e.g. a post-login re-create of AppServices) — re-pushes the active
  /// token so the freshly-established session registers it this time.
  static Future<void> ensureResolved(
    PushRegistrationService registration,
  ) async {
    final existing = instance;
    if (existing != null) {
      await existing._active?.registerToken();
      return;
    }
    final manager = PushManager._();
    instance = manager;
    if (!AppConfig.enableNotifications) return;
    if (!Platform.isAndroid) return; // UP has no iOS impl; FCM needs APNs
    if (AppConfig.enableFcm) {
      try {
        final fcm = FcmTransport(registration: registration, onSync: syncFromPush);
        if (await fcm.init()) manager._active = fcm;
      } catch (e) {
        debugPrint('push: FCM unavailable — $e');
      }
    }
    if (manager._active == null) {
      try {
        final up =
            UnifiedPushTransport(registration: registration, onSync: syncFromPush);
        if (await up.init()) manager._active = up;
      } catch (e) {
        debugPrint('push: Unified Push unavailable — $e');
      }
    }
    debugPrint('push: delivery = ${manager.activeLabel}');

    // ── Conditional fallback policy ────────────────────────────────────
    // A push transport active → the fallback tiers are unnecessary: tell
    // the native side to skip the keep-alive FGS (MainActivity reads this
    // flag on onStop) and cancel the 15-minute WorkManager poller (FCM/UP
    // already trigger a sync on every event). No transport → fallback
    // machinery stays exactly as before.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(pushActivePrefsKey, manager._active != null);
    if (manager._active != null) {
      try {
        await Workmanager().cancelByUniqueName(backgroundTaskName);
      } catch (e) {
        debugPrint('push: poller cancel failed: $e');
      }
    }
  }

  /// Settings status row text.
  String get activeLabel => _active?.label ?? fallbackLabel;

  /// Test seam: install a resolved manager with a known transport without
  /// touching any platform plugin.
  @visibleForTesting
  static void instanceForTest(PushTransport transport) {
    final manager = PushManager._().._active = transport;
    instance = manager;
  }
}

/// A push arrived (FCM data message or Unified Push message): check for
/// new candidates NOW instead of waiting for the 15-minute poll.
///
/// Isolate-aware:
///  - Main isolate (app alive): the singletons exist — route through the
///    LIVE handlers (identical to an SSE ping), so suppression (chat
///    open), master toggles and tap handling all apply, and notifications
///    show through the app's shared notifier.
///  - Background isolate (app was killed): no singletons — run the
///    worker-style full pipeline (fresh session from prefs, fresh plugin
///    instance, same NotifiedTracker dedupe).
Future<void> syncFromPush() async {
  final live = MessageNotifications.instance;
  if (live != null) {
    await live.handleUnreadPing();
    await SocialNotifications.instance?.handleNotificationPing();
    return;
  }
  await runBackgroundSources(backgroundSources());
}
