import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/notifications_service.dart';
import 'message_notifications.dart';
import 'notification_source.dart';
import 'social_notification_source.dart';

/// Social notifications (likes, comments, mentions, follows) — every
/// realtime `notification` SSE ping (the sidecar's per-user push,
/// published by create_notification.php) surfaces as a DEVICE notification,
/// UNLESS the in-app notification drawer is open AND the app is
/// foregrounded (minimized still notifies — the same rule as messages).
///
/// The ping payload only has the unread count, so the service fetches
/// GET ?list=1 (the same read-only worker shape) and notifies on the
/// NEWEST unread bundles, deduped by bundle id (one ping per new event;
/// a new like on an already-notified post is a NEW bundle and re-notifies).
/// Dedupe identity and the tracker are SHARED with the background worker
/// (same keys, same persisted set) — the two paths never double-notify.
///
/// A master toggle ('notifications_enabled', Settings) gates the whole
/// feature; the Settings screen controls it.
class SocialNotifications with WidgetsBindingObserver {
  SocialNotifications({
    required this.notifier,
    required this.notificationsFactory,
    Future<SharedPreferences> Function()? prefsFactory,
  }) : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  /// The app-wide singleton. Set by AppServices.create (first call wins —
  /// later creates reuse it so the drawer-open count stays consistent).
  static SocialNotifications? instance;

  static const String enabledPrefsKey = 'notifications_enabled';

  /// The SHARED plugin-backed notifier (owned by the messages singleton —
  /// the plugin initializes exactly once for the whole app). Only
  /// [LocalNotifier.showSocialNotification] is used from here.
  final LocalNotifier notifier;
  final Future<NotificationsService> Function() notificationsFactory;
  final Future<SharedPreferences> Function() _prefsFactory;

  bool _enabled = true; // cached; loaded from prefs in init()
  int _drawerOpenCount = 0;
  bool _appActive = true; // WidgetsBindingObserver; true until told otherwise

  bool get enabled => _enabled;
  bool get drawerOpen => _drawerOpenCount > 0;
  bool get appActive => _appActive;

  /// One-time boot: master-toggle load + lifecycle observer. The plugin
  /// itself was already initialized by the messages singleton (shared
  /// notifier) — no permission request here (same OS permission).
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final prefs = await _prefsFactory();
      _enabled = prefs.getBool(enabledPrefsKey) ?? true;
    } catch (_) {
      // Never break the app — defaults stay on.
    }
  }

  /// NotificationsScreen lifecycle: the drawer is on screen.
  void setDrawerOpen(bool open) {
    if (open) {
      _drawerOpenCount++;
    } else if (_drawerOpenCount > 0) {
      _drawerOpenCount--;
    }
    // Mirror to prefs so the BACKGROUND worker (a separate isolate that
    // cannot see this in-memory count) also stays quiet while the user
    // is looking at the drawer.
    unawaited(_prefsFactory().then((prefs) =>
        SocialNotificationSource.setDrawerOpenPrefs(
            prefs, _drawerOpenCount > 0)));
  }

  /// App foreground state — minimized counts as "not looking".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
  }

  /// Called on every `notification` realtime ping. Skips when the user is
  /// looking at the drawer; otherwise fetches the newest unread bundles and
  /// notifies. Candidate identity + dedupe are SHARED with the background
  /// worker, so the two paths never double-notify.
  ///
  /// debugPrints are DIAGNOSTIC (SN: ...) — every silent exit is named so
  /// a device-side "no alert" report is one logcat read.
  Future<void> handleNotificationPing() async {
    debugPrint('SN: ping _enabled=$_enabled drawerOpen=$drawerOpen '
        'appActive=$appActive');
    if (!_enabled) return;
    if (drawerOpen && appActive) {
      debugPrint('SN: suppressed (drawer open, app active)');
      return;
    }
    try {
      final service = await notificationsFactory();
      final items = await service.list();
      debugPrint('SN: list -> ${items.length} bundles');
      final prefs = await _prefsFactory();
      final tracker = NotifiedTracker(prefs);
      final candidates = SocialNotificationSource.candidatesFrom(items);
      debugPrint('SN: candidates -> ${candidates.map((c) => c.key).toList()}');
      for (final candidate in candidates) {
        final seen = tracker.contains(candidate.key);
        debugPrint('SN: candidate ${candidate.key} alreadySeen=$seen');
        if (seen) continue;
        debugPrint('SN: showing ${candidate.key}');
        await notifier.showSocialNotification(
          notificationId: candidate.notificationId,
          title: candidate.title,
          body: candidate.body,
        );
        await tracker.add(candidate.key); // only after a successful show
      }
    } catch (e) {
      // The poll / next ping covers it; never surface errors — but log,
      // so a broken path is diagnosable instead of silently dead.
      debugPrint('SN: ping failed: $e');
    }
  }

  /// Master toggle (Settings screen). Persists and re-arms the permission
  /// (the same OS permission as messages — a no-op when already granted).
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    try {
      final prefs = await _prefsFactory();
      await prefs.setBool(enabledPrefsKey, enabled);
    } catch (_) {}
    if (enabled) await notifier.requestPermission();
  }
}
