import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/messages_service.dart';
import '../config/app_config.dart';
import 'message_notification_source.dart';
import 'notification_avatar.dart';
import 'notification_source.dart';

/// Message notifications: every realtime badge ping surfaces as a device
/// notification with a reply action, unless the user is actively reading
/// messages (screen open AND app foregrounded). Gated by a master toggle
/// ('message_notifications_enabled', default ON).
class MessageNotifications with WidgetsBindingObserver {
  MessageNotifications({
    required LocalNotifier notifier,
    required Future<MessagesService> Function() messagesFactory,
    Future<SharedPreferences> Function()? prefsFactory,
  })  : _notifier = notifier,
        _messagesFactory = messagesFactory,
        _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  /// App-wide singleton, set by AppServices.create.
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
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      await _notifier.initialize();
      final prefs = await _prefsFactory();
      _enabled = prefs.getBool(enabledPrefsKey) ?? true;
      if (_enabled) await _notifier.requestPermission();
    } catch (e) {
      // Never break the app, but never be invisible: log, or a failed
      // init (e.g. icon validation) is silently off on device.
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
    // Mirror to prefs so the background worker (a separate isolate that
    // cannot see this in-memory count) also stays quiet.
    unawaited(_prefsFactory().then((prefs) =>
        MessageNotificationSource.setChatOpenPrefs(
            prefs, _messagesOpenCount > 0)));
  }

  /// Minimized counts as not reading; mirror that to prefs so the
  /// background worker alerts while the app is backgrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    unawaited(_prefsFactory().then((prefs) =>
        MessageNotificationSource.setChatOpenPrefs(
            prefs, _appActive && _messagesOpenCount > 0)));
  }

  /// On every `message_unread` ping: skip while actively reading, else
  /// fetch the newest unread message per conversation and notify.
  /// Candidate identity and dedupe are shared with the background worker.
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
          avatarPath: candidate.avatarPath,
        );
        await tracker.add(candidate.key); // only after a successful show
      }
    } catch (e) {
      // The badge poll / next ping covers it; log so a dead path is
      // diagnosable instead of silently dead.
      debugPrint('MN: unread ping failed: $e');
    }
  }

  /// True when the OS currently permits notifications (Android 13+
  /// runtime permission; pre-13 always true); assumed true if the check
  /// itself fails.
  Future<bool> osNotificationsEnabled() async {
    try {
      return await _notifier.areNotificationsEnabled();
    } catch (_) {
      return true;
    }
  }

  /// Deep-link to the OS notification settings for this app; a no-op
  /// failure is fine, the user can reach it manually.
  Future<void> openOsNotificationSettings() async {
    try {
      await _notifier.openAppNotificationSettings();
    } catch (e) {
      debugPrint('MessageNotifications: open settings failed: $e');
    }
  }

  /// Foreground reply action: send the typed text into the conversation.
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
      // A drawer reply must never crash the app.
    }
  }

  /// Master toggle (Settings screen); persists and re-arms the permission.
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

/// Background-isolate reply: builds its own session from prefs, so a
/// quick reply works even when the app is terminated.
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
    String? avatarPath,
  });

  /// Social alert (likes/comments/mentions): plain channel, no reply
  /// action (you can't reply to a like from the drawer).
  Future<void> showSocialNotification({
    required int notificationId,
    required String title,
    required String body,
  });
}

/// Channel + reply action for MESSAGES, one source of truth shared by
/// the live notifier and the background worker isolate.
const _channelId = 'messages';
const _channelName = 'Messages';
const _channelDescription = 'New message notifications';
const _icon = 'ic_stat_enclavd';

/// SOCIAL channel: plain, no actions; silencable independently of
/// messages in the OS notification settings.
const _socialChannelId = 'notifications';
const _socialChannelName = 'Notifications';
const _socialChannelDescription = 'Likes, comments and mentions';

/// Renders one message notification through the given plugin instance.
/// groupConversation false (1:1): the title IS the sender, so the bubble
/// shows no sender label; the avatar is a local file or the initial-letter
/// fallback.
Future<void> showMessageNotificationWith(
  FlutterLocalNotificationsPlugin plugin, {
  required int notificationId,
  required String senderName,
  required String message,
  required int conversationId,
  String? avatarPath,
}) async {
  try {
    final avatarFile = avatarPath == null || avatarPath.isEmpty
        ? null
        : await resolveNotificationAvatar(
            avatarPath,
            baseUrl: AppConfig.apiBaseUrl,
          );
    await plugin.show(
      id: notificationId,
      title: senderName,
      body: message,
      notificationDetails: NotificationDetails(
        android: _messageNotificationDetails(
            senderName, message, conversationId, avatarFile),
      ),
      payload: 'c:$conversationId',
    );
  } catch (e) {
    // The avatar is cosmetic: retry without it, Android falls back to
    // the initial-letter placeholder. Only a double failure propagates.
    debugPrint('MN: show failed ($e) - retrying without the avatar icon');
    await plugin.show(
      id: notificationId,
      title: senderName,
      body: message,
      notificationDetails: NotificationDetails(
        android: _messageNotificationDetails(
            senderName, message, conversationId, null),
      ),
      payload: 'c:$conversationId',
    );
  }
}

/// Message notification details: MessagingStyle + drawer reply action.
/// [avatarFile] is a LOCAL file path or null; the icon is purely cosmetic.
AndroidNotificationDetails _messageNotificationDetails(
  String senderName,
  String message,
  int conversationId,
  String? avatarFile,
) {
  return AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDescription,
    importance: Importance.high,
    priority: Priority.high,
    // MessagingStyle renders the incoming message as a bubble from
    // [senderName]; a drawer reply appends as an outgoing message from
    // the user's person, labeled "Me". groupConversation false = 1:1:
    // sender names are NOT repeated (the title IS the sender).
    styleInformation: MessagingStyleInformation(
      const Person(key: 'me', name: 'Me'),
      conversationTitle: senderName,
      groupConversation: false,
      messages: [
        Message(
          message,
          DateTime.now(),
          Person(
            key: 'them',
            name: senderName,
            // BitmapFilePathAndroidIcon, NOT FilePathAndroidBitmap (a
            // different interface - casting it threw a _TypeError that
            // killed every notification with a downloaded avatar).
            icon: avatarFile == null
                ? null
                : BitmapFilePathAndroidIcon(avatarFile),
          ),
        ),
      ],
    ),
    // The drawer's quick reply: inline text input (v22 shape: inputs,
    // not showsUserInput).
    actions: <AndroidNotificationAction>[
      const AndroidNotificationAction(
        MessageNotifications.replyActionId,
        'Reply',
        inputs: [
          AndroidNotificationActionInput(label: 'Reply'),
        ],
      ),
    ],
  );
}

/// Renders one SOCIAL notification (like/comment/mention alert) through
/// the given plugin instance. No MessagingStyle and no actions: an alert
/// is not a conversation.
Future<void> showSocialNotificationWith(
  FlutterLocalNotificationsPlugin plugin, {
  required int notificationId,
  required String title,
  required String body,
}) async {
  const details = AndroidNotificationDetails(
    _socialChannelId,
    _socialChannelName,
    channelDescription: _socialChannelDescription,
    importance: Importance.high,
    priority: Priority.high,
  );
  await plugin.show(
    id: notificationId,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(android: details),
  );
}

/// Plugin-backed implementation; routes callbacks to the live instance
/// or the self-contained background reply.
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
    String? avatarPath,
  }) =>
      showMessageNotificationWith(
        _plugin,
        notificationId: notificationId,
        senderName: senderName,
        message: message,
        conversationId: conversationId,
        avatarPath: avatarPath,
      );

  @override
  Future<void> showSocialNotification({
    required int notificationId,
    required String title,
    required String body,
  }) =>
      showSocialNotificationWith(
        _plugin,
        notificationId: notificationId,
        title: title,
        body: body,
      );
}
