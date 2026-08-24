import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api/api_client.dart';
import 'daily_quote_widget.dart';

/// A daily quote, exactly as the API serves it: text, author and tags.
class QuoteData {
  const QuoteData({
    required this.text,
    required this.author,
    required this.tags,
  });

  final String text;
  final String author;
  final List<String> tags;
}

/// Daily quote delivery: ONE notification per day at a RANDOM time between
/// 06:00 and 20:00 LOCAL, plus the home-screen widget showing today's quote.
///
/// Mechanics (no new native machinery — reuses the existing WorkManager +
/// flutter_local_notifications stack):
///  - A one-shot WorkManager task is armed with `initialDelay` = time until
///    the next random slot. The task runs even when the app is swiped away
///    (system service), fetches today's quote from api/v1/quote with the
///    persisted session, shows the notification, refreshes the widget, then
///    arms TOMORROW's random slot. After a run nothing is pending, so the
///    next `registerOneOffTask` is a fresh registration.
///  - App starts arm a slot ONLY if none is pending (ExistingWorkPolicy.keep
///    preserves an already-armed run instead of re-randomizing it away).
///  - The widget is also refreshed on app foreground when it's stale
///    ([refreshWidgetIfStale], date-gated in prefs) — covers the case where
///    the OS delayed or dropped the background run.
///  - The notification is its own channel ('daily_quote') so users can
///    silence it independently in OS settings; the app-side Settings toggle
///    arms/cancels the whole pipeline.
class DailyQuoteService {
  DailyQuoteService._();

  static const String taskName = 'enclavd-daily-quote';

  /// App-side master toggle for the feature (Settings screen).
  static const String enabledPrefsKey = 'daily_quote_enabled';

  /// Local date (YYYY-MM-DD) the widget was last refreshed with today's
  /// quote — used by [refreshWidgetIfStale] to avoid refetching every start.
  static const String widgetDatePrefsKey = 'daily_quote_widget_date';

  static const int _notificationId = 10001; // fixed id: one slot per day
  static const String _channelId = 'daily_quote';
  static const String _channelName = 'Daily quote';
  static const String _channelDescription = "Today's quote, once a day";

  /// Random-time window: 06:00–20:00 local, 20:00 exclusive.
  static const int _windowStartHour = 6;
  static const int _windowLengthMinutes = 14 * 60; // 840 → up to 19:59

  /// The next delivery slot: today at a random minute in [06:00, 20:00)
  /// when that is still ahead of [now], otherwise tomorrow. [random] is
  /// injectable for deterministic tests.
  @visibleForTesting
  static DateTime nextSlot(DateTime now, {Random? random}) {
    final rng = random ?? Random();
    final base = DateTime(now.year, now.month, now.day)
        .add(const Duration(hours: _windowStartHour));
    final candidate =
        base.add(Duration(minutes: rng.nextInt(_windowLengthMinutes)));
    return candidate.isAfter(now)
        ? candidate
        : candidate.add(const Duration(days: 1));
  }

  static bool isEnabled(SharedPreferences prefs) =>
      prefs.getBool(enabledPrefsKey) ?? true;

  /// Arms the next run. `keep` preserves an already-armed slot (app starts
  /// must not re-randomize an armed run away); after a completed run there
  /// is nothing pending, so this registers fresh. No-op when disabled.
  static Future<void> scheduleNextRun() async {
    final prefs = await SharedPreferences.getInstance();
    if (!isEnabled(prefs)) return;
    final now = DateTime.now();
    final delay = nextSlot(now).difference(now);
    await Workmanager().registerOneOffTask(
      taskName,
      taskName,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
    debugPrint('daily quote: next run in ${delay.inMinutes} min');
  }

  /// Cancels the armed run (Settings toggle off).
  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(taskName);
    debugPrint('daily quote: cancelled');
  }

  /// The background run (headless isolate — same contract as the poller):
  /// fresh ApiClient from prefs (pinned UA rides the default factory),
  /// fresh notification plugin instance. Fetches today's quote, shows the
  /// daily notification, refreshes the widget, then arms tomorrow's slot.
  ///
  /// Every step is independently guarded: a failure shows nothing but the
  /// next day's slot is still armed, so the feature self-heals.
  static Future<void> runTask() async {
    final prefs = await SharedPreferences.getInstance();
    if (!isEnabled(prefs)) {
      debugPrint('daily quote: disabled, not rescheduling');
      return;
    }

    final api = ApiClient(store: PrefsSessionStore(prefs));
    await api.restoreSession();
    if (!api.hasSession) {
      debugPrint('daily quote: no session, skipping');
      return; // a future app start re-arms
    }

    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_enclavd'),
      ),
    );

    final QuoteData? quote = await _fetchToday(api);
    if (quote != null) {
      try {
        await plugin.show(
          id: _notificationId,
          title: '💬 Quote of the day',
          body: '“${quote.text}”\n— ${quote.author}',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              channelDescription: _channelDescription,
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
          ),
          payload: 'quote',
        );
        debugPrint('daily quote: notification shown');
      } catch (e) {
        debugPrint('daily quote: notification failed: $e');
      }
      await DailyQuoteWidget.push(
        text: quote.text,
        author: quote.author,
        tags: quote.tags,
      );
      await prefs.setString(widgetDatePrefsKey, _todayKey());
    } else {
      debugPrint('daily quote: fetch failed, nothing delivered');
    }

    await scheduleNextRun(); // armed regardless — tomorrow retries
  }

  /// Foreground refresh for the widget: once per LOCAL day, if a session
  /// exists and the feature is enabled, fetch today's quote and push it to
  /// the widget. Silent and cheap (date-gated) — call from app start/login.
  static Future<void> refreshWidgetIfStale() async {
    final prefs = await SharedPreferences.getInstance();
    if (!isEnabled(prefs)) return;
    if (prefs.getString(widgetDatePrefsKey) == _todayKey()) return; // fresh
    final api = ApiClient(store: PrefsSessionStore(prefs));
    await api.restoreSession();
    if (!api.hasSession) return;
    final quote = await _fetchToday(api);
    if (quote == null) return;
    await DailyQuoteWidget.push(
      text: quote.text,
      author: quote.author,
      tags: quote.tags,
    );
    await prefs.setString(widgetDatePrefsKey, _todayKey());
  }

  /// GET-ward fetch of the daily quote (POST /api/v1/quote {action:today} —
  /// the same idempotent-per-day call the web toast uses; CSRF rides the
  /// persisted session's PHP sid via ApiClient.postJson).
  static Future<QuoteData?> _fetchToday(ApiClient api) async {
    try {
      final data = await api.postJson('/api/v1/quote', {'action': 'today'});
      final q = data['quote'];
      if (q is! Map<String, dynamic>) return null;
      return QuoteData(
        text: (q['text'] ?? '').toString(),
        author: (q['author'] ?? '').toString(),
        tags: (q['tags'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
    } catch (e) {
      debugPrint('daily quote: fetch failed: $e');
      return null;
    }
  }

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }
}
