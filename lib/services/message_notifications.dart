import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/messages_service.dart';
import 'message_notification_source.dart';
import 'notification_source.dart';

/// Message notifications — every realtime badge ping (SSE `message_unread`)
/// surfaces as a device notification with a reply action, UNLESS the user is
/// actively reading messages (messages screen open AND app foregrounded;
/// minimized/backgrounded still notifies — that is the point of the ping).
///
/// The notification carries the NEWEST unread message (the ping payload only
/// has a count, so we fetch `?unread=1` — the same read-only worker shape),
/// keyed by conversation so a conversation's older notification is replaced,
/// and deduped by message id so one ping per new message.
///
/// The Reply action posts via api/v1 {action:'reply'} — the session lives in
/// SharedPreferences, so even a reply from the drawer while the app is
/// backgrounded (or the notification's own background isolate) can send it.
///
/// A master toggle ('message_notifications_enabled', default ON) gates the
/// whole feature; the Settings screen controls it.
class MessageNotifications with WidgetsBindingObserver {
  MessageNotifications({
    required LocalNotifier notifier,
    required Future<MessagesService> Function() messagesFactory,
    Future<SharedPreferences> Function()? prefsFactory,
  })  : _notifier = notifier,
        _messagesFactory = messagesFactory,
        _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  /// The app-wide singleton. Set by AppServices.create (first call wins —
  /// later creates reuse it, so the plugin is initialized exactly once and
  /// the messages-open count stays consistent across screen instances).
  static MessageNotifications? instance;

  static const String enabledPrefsKey = 'message_notifications_enabled';
  static const String replyActionId = 'reply';

  final LocalNotifier _notifier;
  final Future<MessagesService> Function() _messagesFactory;
  final Future<SharedPreferences> Function() _prefsFactory;

  bool _enabled = true; // cached; loaded from prefs in init()
  int _messagesOpenCount = 0;
  bool _appActive = true; // WidgetsBindingObserver; true until told otherwise

  bool get enabled => _enabled;
  bool get messagesOpen => _messagesOpenCount > 0;
  bool get appActive => _appActive;

  /// One-time boot: plugin init, master-toggle load, permission request.
  /// Swallows every error — notifications must never break the app.
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      await _notifier.initialize();
      final prefs = await _prefsFactory();
      _enabled = prefs.getBool(enabledPrefsKey) ?? true;
      if (_enabled) await _notifier.requestPermission();
    } catch (e) {
      // Never break the app, but NEVER be invisible either — a failed
      // init here (e.g. the plugin's icon validation) means no popup and
      // silently off notifications; that has to be diagnosable on-device.
      debugPrint('MessageNotifications: init failed: $e');
    }
  }

  /// MessagesScreen / ChatScreen lifecycle: the thread is on screen.
  void setMessagesOpen(bool open) {
    if (open) {
      _messagesOpenCount++;
    } else if (_messagesOpenCount > 0) {
      _messagesOpenCount--;
    }
    // Mirror to prefs so the BACKGROUND worker (a separate isolate that
    // cannot see this in-memory count) also stays quiet while the user
    // is reading the thread.
    unawaited(_prefsFactory().then((prefs) =>
        MessageNotificationSource.setChatOpenPrefs(
            prefs, _messagesOpenCount > 0)));
  }

  /// App foreground state — minimized counts as "not reading".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
  }

  /// Called on every `message_unread` realtime ping (the badge event).
  /// Skips when the user is actively reading messages; otherwise fetches
  /// the newest unread message per conversation and notifies. Candidate
  /// identity and dedupe are SHARED with the background worker (same
  /// keys, same persisted tracker), so the two paths never double-notify
  /// and a notification shown by one is never repeated by the other.
  ///
  /// The debugPrints are DIAGNOSTIC (0.3.4): every silent exit is named,
  /// so a device-side "no notification" report becomes one logcat read.
  Future<void> handleUnreadPing() async {
    debugPrint('MN: ping _enabled=$_enabled messagesOpen=$messagesOpen '
        'appActive=$appActive');
    if (!_enabled) return;
    if (messagesOpen && appActive) {
      debugPrint('MN: suppressed (messages screen open, app active)');
      return;
    }
    try {
      final messages = await _messagesFactory();
      final unread = await messages.unreadMessages();
      debugPrint('MN: unread fetch -> ${unread.length} rows');
      if (unread.isEmpty) {
        debugPrint('MN: no unread rows');
        return;
      }
      final prefs = await _prefsFactory();
      final tracker = NotifiedTracker(prefs);
      final candidates = MessageNotificationSource.candidatesFrom(unread);
      debugPrint('MN: candidates -> ${candidates.map((c) => c.key).toList()}');
      for (final candidate in candidates) {
        final seen = tracker.contains(candidate.key);
        debugPrint('MN: candidate ${candidate.key} alreadySeen=$seen');
        if (seen) continue;
        final conversationId =
            conversationIdFromPayload(candidate.payload) ?? 0;
        debugPrint('MN: showing ${candidate.key}');
        await _notifier.showMessageNotification(
          notificationId: candidate.notificationId, // replace per conversation
          senderName: candidate.title,
          message: candidate.body,
          conversationId: conversationId,
        );
        await tracker.add(candidate.key); // only after a successful show
      }
    } catch (e) {
      // The badge poll / next ping covers it; never surface errors — but
      // log, so a broken path is diagnosable instead of silently dead.
      debugPrint('MN: unread ping failed: $e');
    }
  }

  /// True when the OS currently permits notifications (Android 13+
  /// runtime permission; pre-13 always true). Assumed true when the
  /// check itself fails — the caller only warns on a definite denial.
  Future<bool> osNotificationsEnabled() async {
    try {
      return await _notifier.areNotificationsEnabled();
    } catch (_) {
      return true;
    }
  }

  /// Deep-link to the OS notification settings for this app (the
  /// Android notification-permission screen). No-op failure is fine —
  /// the user can reach it manually.
  Future<void> openOsNotificationSettings() async {
    try {
      await _notifier.openAppNotificationSettings();
    } catch (e) {
      debugPrint('MessageNotifications: open settings failed: $e');
    }
  }

  /// Foreground notification-action response (the app is alive). The Reply
  /// action sends the typed text into the conversation the notification
  /// was about. The background isolate uses [replyFromNotification].
  Future<void> handleResponse(NotificationResponse response) async {
    if (response.actionId != replyActionId) return;
    final text = (response.input ?? '').trim();
    if (text.isEmpty) return;
    final conversationId = conversationIdFromPayload(response.payload);
    if (conversationId == null) return;
    try {
      final messages = await _messagesFactory();
      await messages.send(conversationId, text);
    } catch (_) {
      // The sender sees the failure in the thread next time they open it;
      // never crash the app from a drawer reply.
    }
  }

  /// Master toggle (Settings screen). Persists and re-arms the permission.
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    try {
      final prefs = await _prefsFactory();
      await prefs.setBool(enabledPrefsKey, enabled);
    } catch (_) {}
    if (enabled) await _notifier.requestPermission();
  }

  static int? conversationIdFromPayload(String? payload) {
    if (payload == null || !payload.startsWith('c:')) return null;
    return int.tryParse(payload.substring(2));
  }
}

/// Sends the drawer-reply text into the conversation. Used by the
/// notification's BACKGROUND isolate (the app may be terminated): it builds
/// its own session from SharedPreferences — the exact contract the closed-app
/// worker uses — so a quick reply never needs the main isolate alive.
@pragma('vm:entry-point')
Future<void> replyFromNotification(NotificationResponse response) async {
  if (response.actionId != MessageNotifications.replyActionId) return;
  final text = (response.input ?? '').trim();
  if (text.isEmpty) return;
  final conversationId = MessageNotifications.conversationIdFromPayload(
      response.payload);
  if (conversationId == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final api = ApiClient(store: PrefsSessionStore(prefs));
    await api.restoreSession();
    final csrf = await api.fetchCsrfToken();
    if (csrf == null) return;
    final messages = MessagesService(api);
    await messages.send(conversationId, text);
  } catch (_) {
    // Same rule: a drawer reply must never crash anything.
  }
}

/// Thin seam over the plugin so tests never touch platform channels.
abstract class LocalNotifier {
  Future<void> initialize();
  Future<void> requestPermission();

  /// Whether the OS currently allows this app to post notifications
  /// (Android 13+ runtime permission; pre-13 always true).
  Future<bool> areNotificationsEnabled();

  /// Opens the OS notification-settings screen for this app. Returns
  /// whether an activity could be launched.
  Future<bool> openAppNotificationSettings();

  Future<void> showMessageNotification({
    required int notificationId,
    required String senderName,
    required String message,
    required int conversationId,
  });
}

/// Channel + drawer-reply action, ONE source of truth shared by the live
/// notifier and the background worker isolate (each owns its own plugin
/// instance) so the two paths never drift.
const _channelId = 'messages';
const _channelName = 'Messages';
const _channelDescription = 'New message notifications';
const _icon = 'ic_stat_enclavd';

/// Renders one message notification through the given plugin instance.
/// Isolate-agnostic — the worker's freshly-initialized plugin included.
Future<void> showMessageNotificationWith(
  FlutterLocalNotificationsPlugin plugin, {
  required int notificationId,
  required String senderName,
  required String message,
  required int conversationId,
}) async {
  const details = AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDescription,
    importance: Importance.high,
    priority: Priority.high,
    // The drawer's quick reply: a free-form text input rendered inline
    // on the notification (v22 shape: inputs, not showsUserInput).
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(
        MessageNotifications.replyActionId,
        'Reply',
        inputs: [
          AndroidNotificationActionInput(label: 'Reply'),
        ],
      ),
    ],
  );
  await plugin.show(
    id: notificationId,
    title: senderName,
    body: message,
    notificationDetails: const NotificationDetails(android: details),
    payload: 'c:$conversationId',
  );
}

/// The plugin-backed implementation. The foreground callback routes to the
/// live [MessageNotifications] instance; the background callback is the
/// self-contained [replyFromNotification].
class FlutterLocalNotifier implements LocalNotifier {
  FlutterLocalNotifier({required this.onResponse});

  final void Function(NotificationResponse) onResponse;

  final _plugin = FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings(_icon),
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onResponse,
      onDidReceiveBackgroundNotificationResponse: replyFromNotification,
    );
  }

  @override
  Future<void> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  @override
  Future<bool> areNotificationsEnabled() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  @override
  Future<bool> openAppNotificationSettings() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await android?.openAppNotificationSettings() ?? false;
  }

  @override
  Future<void> showMessageNotification({
    required int notificationId,
    required String senderName,
    required String message,
    required int conversationId,
  }) =>
      showMessageNotificationWith(
        _plugin,
        notificationId: notificationId,
        senderName: senderName,
        message: message,
        conversationId: conversationId,
      );
}
