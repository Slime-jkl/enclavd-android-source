import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/notifications_service.dart';
import 'message_notifications.dart';
import 'notification_source.dart';
import 'social_notification_source.dart';

/// Social notifications (likes, comments, mentions, follows): every
/// realtime `notification` SSE ping surfaces as a DEVICE notification,
/// unless the in-app drawer is open AND the app is foregrounded. The ping
/// only carries the unread count, so the service fetches GET ?list=1 (the
/// read-only worker shape) and notifies on the NEWEST unread bundles,
/// deduped by bundle id. Dedupe is SHARED with the background worker.
/// Master toggle: 'notifications_enabled' (Settings).
class SocialNotifications with WidgetsBindingObserver {
  SocialNotifications({
    required this.notifier,
    required this.notificationsFactory,
    Future<SharedPreferences> Function()? prefsFactory,
  }) : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  /// App-wide singleton, set by AppServices.create.
  static SocialNotifications? instance;

  static const String enabledPrefsKey = 'notifications_enabled';

  /// The SHARED plugin-backed notifier (owned by the messages singleton,
  /// so the plugin initializes exactly once); only
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

  /// One-time boot: toggle load + lifecycle observer. The plugin itself
  /// was already initialized by the messages singleton (shared notifier),
  /// so no permission request here.
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      final prefs = await _prefsFactory();
      _enabled = prefs.getBool(enabledPrefsKey) ?? true;
    } catch (_) {
      // Never break the app: defaults stay on.
    }
  }

  /// NotificationsScreen lifecycle: the drawer is on screen.
  void setDrawerOpen(bool open) {
    if (open) {
      _drawerOpenCount++;
    } else if (_drawerOpenCount > 0) {
      _drawerOpenCount--;
    }
    // Mirror to prefs so the background worker (a separate isolate that
    // cannot see this in-memory count) also stays quiet.
    unawaited(_prefsFactory().then((prefs) =>
        SocialNotificationSource.setDrawerOpenPrefs(
            prefs, _drawerOpenCount > 0)));
  }

  /// Minimized counts as "not looking"; mirrored to prefs so the
  /// background worker applies the same rule.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    unawaited(_prefsFactory().then((prefs) =>
        prefs.setBool(SocialNotificationSource.appActivePrefsKey, _appActive)));
  }

  /// On every `notification` ping: skip when the drawer is open and the
  /// app is active; else fetch the newest unread bundles and notify.
  /// Candidate identity + dedupe are SHARED with the background worker,
  /// so the two paths never double-notify.
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
      // The poll / next ping covers it; log so a dead path is diagnosable.
      debugPrint('SN: ping failed: $e');
    }
  }

  /// Master toggle (Settings screen); persists and re-arms the permission
  /// (same OS permission as messages - a no-op when already granted).
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    try {
      final prefs = await _prefsFactory();
      await prefs.setBool(enabledPrefsKey, enabled);
    } catch (_) {}
    if (enabled) await notifier.requestPermission();
  }
}
