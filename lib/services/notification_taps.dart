import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../main.dart';
import '../screens/messages_screen.dart';
import '../screens/notifications_screen.dart';
import 'message_notifications.dart';

/// Where a notification tap lands.
///
///   'quote'         - the daily-quote deep link (Quote of the day settings).
///   'c:<id>'        - a message: the inbox, where the thread lives.
///   'n:<bundle id>' - a social alert: the in-app notification drawer, the
///                     screen that lists it.
///
/// The drawer push needs the session's services AND a live navigator, so a
/// tap that cold-started the app is parked and finished by [resolvePending]
/// (called by the splash/login gate once the session is past it).
///
/// Swipes never come through here: the plugin reports a dismissal on a
/// background isolate, whether or not the app is alive (see
/// DismissedNotifications).
class NotificationTaps {
  NotificationTaps._();

  static LocalNotifier? _notifier;

  /// A tap that arrived before the app could route it (cold start, no
  /// session yet). Resolved after the gate.
  static String? _pending;

  /// A launch tap is read back at most once per process: the activity's
  /// launch intent stays readable, so a later login would otherwise replay
  /// it and reopen the screen.
  static bool _launchConsumed = false;

  /// The shared plugin notifier, so a cold-start tap can be read back.
  static void attach(LocalNotifier notifier) => _notifier = notifier;

  /// Test seams: the real screens load over the network on build, so routing
  /// tests swap them for inert widgets.
  @visibleForTesting
  static Widget Function(AppServices services) drawerBuilder = (services) =>
      NotificationsScreen(
        notifications: services.notifications,
        realtime: services.realtime,
      );

  @visibleForTesting
  static Widget Function() messagesBuilder = () => const MessagesScreen();

  /// Live callback: the app was running when the user tapped.
  static void handleResponse(NotificationResponse response) {
    switch (response.notificationResponseType) {
      case NotificationResponseType.notificationDismissed:
        // Reported on the background isolate; nothing for the UI to do.
        return;
      case NotificationResponseType.selectedNotificationAction:
        // Quick reply from the tray.
        MessageNotifications.instance?.handleResponse(response);
        return;
      case NotificationResponseType.selectedNotification:
        handleTap(response.payload);
        return;
    }
  }

  /// Routes a tap's payload; parks it when there is nothing to push onto
  /// yet, so a cold start still lands on the right screen.
  static void handleTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    if (payload == 'quote') {
      QuoteDeepLink.requestOpen();
      return;
    }
    final nav = navigatorKey.currentState;
    if (nav == null || !nav.mounted) {
      _pending = payload;
      return;
    }
    if (payload.startsWith('c:')) {
      _pending = null;
      nav.push(MaterialPageRoute<void>(builder: (_) => messagesBuilder()));
      return;
    }
    if (!payload.startsWith('n:')) return; // not a notification we route
    final services = AppServices.current;
    if (services == null) {
      _pending = payload; // signed out: the drawer needs the session
      return;
    }
    _pending = null;
    nav.push(MaterialPageRoute<void>(
      builder: (_) => drawerBuilder(services),
    ));
  }

  /// Finishes whatever tap brought the app up, plus anything parked while
  /// it had no session. Called by the splash/login gate.
  static Future<void> resolvePending() async {
    final notifier = _notifier;
    if (notifier != null && !_launchConsumed) {
      try {
        final payload = await notifier.launchPayload();
        if (payload != null) {
          _launchConsumed = true; // never replay it on a later gate
          handleTap(payload);
        }
      } catch (e) {
        // Plugin unavailable (tests): nothing to resolve.
        debugPrint('taps: launch details failed: $e');
      }
    }
    final parked = _pending;
    _pending = null;
    if (parked != null) handleTap(parked);
  }
}
