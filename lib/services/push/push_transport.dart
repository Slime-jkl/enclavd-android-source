import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../config/app_config.dart';
import 'transport_selector.dart';
import '../message_notifications.dart';
import '../notification_worker.dart';
import 'push_registration_service.dart';
import '../social_notifications.dart';
import 'unified_push_transport.dart';

/// A background push transport: something that can wake the app's process
/// when the server has new data, instead of waiting up to 15 minutes for
/// the WorkManager poll. Its only job is to turn an incoming push into a
/// [syncFromPush] call; the existing two-path notification pipeline (with
/// its cross-path NotifiedTracker dedupe) is reused verbatim.
abstract class PushTransport {
  /// Short transport id ('fcm' | 'unifiedpush'), sent to the server as
  /// the registration transport.
  String get id;

  /// Human label for the settings status row.
  String get label;

  /// Bring the transport up: bind handlers, obtain a token/endpoint and
  /// register it with the server. True when the transport is ACTIVE on
  /// this build/device; throws when unusable (the manager falls through).
  Future<bool> init();

  /// (Re)send the current token/endpoint to the server. Called on every
  /// app start and after a fresh login - the session may not have existed
  /// when [init] ran.
  Future<void> registerToken();
}

/// Resolves and owns the best push transport for the current build and
/// device, and turns every incoming push into a notification sync.
/// Order: play/dev = FCM -> Unified Push -> polling; fdroid = Unified
/// Push -> polling (that build never touches Google Play services). The
/// 15-minute poll is always registered as the safety net; the shared
/// dedupe makes the overlap harmless.
class PushManager {
  PushManager._();

  static PushManager? instance;

  /// The active transport, or null when only the polling fallback is
  /// available on this device.
  PushTransport? _active;
  PushTransport? get active => _active;

  static const String fallbackLabel = '15-minute background checks';

  /// Native side reads this (prefixed "flutter.") to skip the keep-alive
  /// foreground service when a push transport is active. Defaults false
  /// (fallback machinery on).
  static const String pushActivePrefsKey = 'push_transport_active';

  /// Binds FCM's killed-process callback before the engine starts; no-op
  /// on F-Droid builds and when notifications are compiled out.
  static void bindBackgroundHandlers() {
    if (!AppConfig.enableNotifications || !AppConfig.enableFcm) return;
    FcmTransport.bindBackgroundHandler();
  }

  /// Resolves the transport once (idempotent); when already resolved
  /// (post-login re-create), re-pushes the active token so the fresh
  /// session registers it.
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
        debugPrint('push: FCM unavailable - $e');
      }
    }
    if (manager._active == null) {
      try {
        final up =
            UnifiedPushTransport(registration: registration, onSync: syncFromPush);
        if (await up.init()) manager._active = up;
      } catch (e) {
        debugPrint('push: Unified Push unavailable - $e');
      }
    }
    debugPrint('push: delivery = ${manager.activeLabel}');

    // Push transport active -> skip the keep-alive FGS (MainActivity
    // reads this flag on onStop) and cancel the 15-min poller (each push
    // already triggers a sync). No transport -> fallback stays as before.
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
/// new candidates NOW instead of waiting for the 15-minute poll. Main
/// isolate -> live handlers (suppression, toggles, tap handling all
/// apply); background isolate -> worker-style full pipeline, same dedupe.
Future<void> syncFromPush() async {
  final live = MessageNotifications.instance;
  if (live != null) {
    await live.handleUnreadPing();
    await SocialNotifications.instance?.handleNotificationPing();
    return;
  }
  await runBackgroundSources(backgroundSources());
}
