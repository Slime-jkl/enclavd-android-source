import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api/api_client.dart';
import 'daily_quote_service.dart';
import 'message_notification_source.dart';
import 'message_notifications.dart';
import 'notification_source.dart';
import 'social_notification_source.dart';

/// Background notification polling via WorkManager — the ONLY native
/// cover for the states the live SSE/WS path cannot reach: app swiped
/// away or process killed (Android freezes/kills the sockets; no Dart
/// code runs until the next launch). WorkManager is a system service,
/// so the task survives both.
///
/// The worker is intentionally source-agnostic. Adding a future
/// notification type (post likes/comments via
/// /api/v1/notifications?list=1, mentions, ...) is ONE line in
/// [backgroundSources] — the dedupe, session handling and notification
/// plumbing are shared.
///
/// Honest limits (Android platform reality, same as the WebView
/// wrapper's worker): the minimum periodic interval is 15 minutes and
/// WorkManager makes NO timing guarantees — Doze/App-Standby delay
/// execution. This is the fallback channel, not the live one.
const String backgroundTaskName = 'enclavd-notifications-poll';

const Duration pollInterval = Duration(minutes: 15); // Android's hard minimum

/// Registry of everything the background poller checks. Plug in new
/// notification domains here — one line each.
List<NotificationSource> backgroundSources() => [
      MessageNotificationSource(),
      SocialNotificationSource(),
    ];

/// Schedules the periodic poller. Idempotent: the unique name + update
/// policy replace the previous request instead of stacking another, so
/// calling this on every app start is safe and self-healing.
Future<void> registerBackgroundNotifications() async {
  await Workmanager().registerPeriodicTask(
    backgroundTaskName,
    backgroundTaskName,
    frequency: pollInterval,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// The headless entry point WorkManager wakes (its own Flutter engine,
/// no UI, possibly long after the app was killed). Top-level +
/// @pragma so the AOT snapshot keeps it. Every failure returns true —
/// WorkManager treats false as a failed run; a transient blip must not
/// burn the backoff chain, the next tick retries.
///
/// Branches on the task name: the daily-quote one-shot (random-time slot,
/// see DailyQuoteService) and the widget rollover one-shot (UTC-midnight
/// widget refresh) get their own handlers; everything else falls through
/// to the periodic source poller.
@pragma('vm:entry-point')
void notificationDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      if (taskName == DailyQuoteService.taskName) {
        await DailyQuoteService.runTask();
      } else if (taskName == DailyQuoteService.rolloverTaskName) {
        await DailyQuoteService.runMidnightRollover();
      } else {
        await runBackgroundSources(backgroundSources());
      }
    } catch (e) {
      debugPrint('notification worker: $e');
    }
    return true;
  });
}

/// The worker run itself, separated from the dispatcher so tests can
/// exercise it without the platform plugin. debugPrints are DIAGNOSTIC
/// (0.3.4) — the worker is otherwise a black box on-device.
Future<void> runBackgroundSources(List<NotificationSource> sources) async {
  final prefs = await SharedPreferences.getInstance();
  final api = ApiClient(store: PrefsSessionStore(prefs));
  await api.restoreSession();
  if (api.sessionCookies.isEmpty) {
    debugPrint('worker: no session, skipping');
    return; // logged out — the worker has nothing to poll until login
  }

  // This isolate has no plugin state: initialize a fresh instance (the
  // background reply action must be wired here too, so a drawer reply
  // from a worker-shown notification works).
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_enclavd'),
    ),
    onDidReceiveBackgroundNotificationResponse: replyFromNotification,
  );

  final context = SourceContext(api: api, prefs: prefs);
  final tracker = NotifiedTracker(prefs);
  final fresh = await freshCandidates(sources, context, tracker: tracker);
  debugPrint('worker: ${fresh.length} fresh candidate(s)');
  for (final candidate in fresh) {
    debugPrint('worker: showing ${candidate.key}');
    try {
      switch (candidate.kind) {
        case CandidateKind.message:
          final conversationId =
              MessageNotifications.conversationIdFromPayload(candidate.payload);
          await showMessageNotificationWith(
            plugin,
            notificationId: candidate.notificationId,
            senderName: candidate.title,
            message: candidate.body,
            conversationId: conversationId ?? 0,
            avatarPath: candidate.avatarPath,
          );
        case CandidateKind.social:
          await showSocialNotificationWith(
            plugin,
            notificationId: candidate.notificationId,
            title: candidate.title,
            body: candidate.body,
          );
      }
      await tracker.add(candidate.key); // only after a successful show
    } catch (e) {
      // ONE broken candidate must never kill the rest of the run (a
      // throwing message show used to abort the whole loop, silently
      // dropping the social candidates behind it — 0.4.2 regression).
      // The candidate stays unmarked, so the next tick retries it.
      debugPrint('worker: candidate ${candidate.key} failed: $e');
    }
  }
}
