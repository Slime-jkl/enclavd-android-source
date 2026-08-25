import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api/api_client.dart';
import 'daily_quote_widget.dart';

/// A daily quote, exactly as the API serves it: id, text, author and tags.
class QuoteData {
  const QuoteData({
    required this.id,
    required this.text,
    required this.author,
    required this.tags,
  });

  final int id;
  final String text;
  final String author;
  final List<String> tags;
}

/// Today's quote plus the user's rating state for it (null = unrated) and
/// the SERVER's quote day (YYYY-MM-DD) — the server's clock decides when a
/// new quote becomes current, so that date (not the device's local day) is
/// what the widget freshness stamp must record.
class TodayQuote {
  const TodayQuote({
    required this.quote,
    required this.rated,
    required this.date,
  });

  final QuoteData quote;
  final String? rated; // 'like' | 'dislike' | null
  final String date; // server quote day, e.g. '2026-08-25'
}

/// A parsed widget rate tap: which action, on which quote.
class RateAction {
  const RateAction({required this.action, required this.quoteId});

  final String action; // 'like' | 'dislike'
  final int quoteId;
}

/// Daily quote delivery: ONE notification per day at a RANDOM time between
/// 06:00 and 20:00 LOCAL, plus the home-screen widget showing today's quote
/// with 👍/👎 buttons that record the rating in the API.
///
/// Mechanics (no new native machinery — reuses the existing WorkManager +
/// flutter_local_notifications stack + home_widget's interactive widgets):
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
///  - The 👍/👎 buttons deliver a broadcast to home_widget's
///    HomeWidgetBackgroundReceiver, which wakes a headless Dart isolate
///    running [quoteWidgetRateCallback] (registered at app start). The tap
///    URI carries the action + quote id; the callback posts the rating with
///    the persisted session and re-renders the widget tinted.
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

  /// URI scheme used by the widget's rate buttons (provider → callback).
  static const String widgetRateScheme = 'enclavdwidget';

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

  /// Parses a widget rate tap URI (`enclavdwidget://like?id=983`). Returns
  /// null when the tap is not a well-formed rate action (foreign tap, bad
  /// id). Pure — unit-tested.
  @visibleForTesting
  static RateAction? parseRateAction(Uri? uri) {
    if (uri == null) return null;
    final action = uri.host; // 'like' | 'dislike'
    if (action != 'like' && action != 'dislike') return null;
    final quoteId = int.tryParse(uri.queryParameters['id'] ?? '');
    if (quoteId == null || quoteId <= 0) return null;
    return RateAction(action: action, quoteId: quoteId);
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

    final TodayQuote? today = await _fetchToday(api);
    if (today != null) {
      // The widget IS the daily surface: when at least one instance sits
      // on the home screen the quote is already in front of the user, so
      // the notification is skipped (no double delivery). The widget is
      // still refreshed and tomorrow's slot armed either way.
      final widgetInUse = await _hasWidgetInstance();
      if (widgetInUse) {
        debugPrint('daily quote: widget present, notification skipped');
      } else {
        try {
          await plugin.show(
            id: _notificationId,
            title: '💬 Quote of the day',
            body: '“${today.quote.text}”\n— ${today.quote.author}',
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
      }
      await pushTodayToWidget(api: api, prefs: prefs, today: today);
    } else {
      debugPrint('daily quote: fetch failed, nothing delivered');
    }

    await scheduleNextRun(); // armed regardless — tomorrow retries
  }

  /// Whether at least one daily-quote widget is pinned on the home screen.
  /// home_widget reports one entry per widget instance on Android. On a
  /// probe failure the safe default is false → the notification fires.
  static Future<bool> _hasWidgetInstance() async {
    try {
      final widgets = await HomeWidget.getInstalledWidgets();
      return widgets.any((w) =>
          (w.androidClassName ?? '').contains('QuoteWidgetProvider'));
    } catch (e) {
      debugPrint('daily quote: widget presence check failed: $e');
      return false;
    }
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
    final today = await _fetchToday(api);
    if (today == null) return;
    await pushTodayToWidget(api: api, prefs: prefs, today: today);
  }

  /// Background entry point for widget rate taps (registered via
  /// HomeWidget.registerInteractivityCallback). Posts the rating with the
  /// persisted session, then re-renders the widget. On a stale/duplicate
  /// tap (server rejects) it re-syncs the widget to the server's truth
  /// instead of leaving dead buttons.
  static Future<void> rateFromWidget(Uri? uri) async {
    final rate = parseRateAction(uri);
    if (rate == null) {
      debugPrint('quote widget: ignoring foreign tap $uri');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!isEnabled(prefs)) return;
    final api = ApiClient(store: PrefsSessionStore(prefs));
    await api.restoreSession();
    if (!api.hasSession) {
      debugPrint('quote widget: no session, rating dropped');
      return; // logged out — the widget can't rate; next login re-pushes
    }
    try {
      final data = await api.postJson(
        '/api/v1/quote',
        {'action': rate.action, 'quote_id': rate.quoteId},
      );
      final rated = (data['rated'] ?? rate.action).toString();
      await DailyQuoteWidget.markRated(quoteId: rate.quoteId, rated: rated);
      debugPrint('quote widget: $rated recorded for quote ${rate.quoteId}');
    } catch (e) {
      // 400 'Quote already rated' (double tap) / 'no current quote' (widget
      // stale across the daily rotation) — re-sync to today's state.
      debugPrint('quote widget: rate failed ($e) — resyncing');
      final today = await _fetchToday(api);
      if (today != null) {
        await pushTodayToWidget(api: api, prefs: prefs, today: today);
      }
    }
  }

  /// Writes today's quote (with the user's rating state) to the widget and
  /// stamps the freshness date so [refreshWidgetIfStale] stays quiet.
  ///
  /// The stamp is the SERVER's quote day ([TodayQuote.date]), NOT the
  /// device's local day. The gate compares the stamp against the local
  /// day, so any offset between the device clock and the server clock
  /// (timezone, skew) makes the gate re-fetch on the next app open until
  /// the server has actually rotated — the widget can never lock onto a
  /// stale quote for a whole day the way a device-day stamp could
  /// (server rotates at UTC midnight; a device ahead/behind would keep
  /// serving yesterday's quote all day).
  ///
  /// The stamp advances ONLY on a successful push: [DailyQuoteWidget.push]
  /// reports failures now, so a plugin hiccup leaves the gate open and the
  /// next start retries, instead of burning the whole day on a failed push.
  static Future<void> pushTodayToWidget({
    required ApiClient api,
    required SharedPreferences prefs,
    required TodayQuote today,
  }) async {
    final ok = await DailyQuoteWidget.push(
      text: today.quote.text,
      author: today.quote.author,
      tags: today.quote.tags,
      quoteId: today.quote.id,
      rated: today.rated,
    );
    if (ok) {
      await prefs.setString(widgetDatePrefsKey, today.date);
    }
  }

  /// Fresh session hook (successful login): drop the freshness stamp so
  /// the very next refresh actually fetches, and fetch right away — a
  /// stale session could have silently starved the widget for days, and
  /// now it catches up immediately instead of trusting the old stamp.
  static Future<void> refreshWidgetNow() async {
    final prefs = await SharedPreferences.getInstance();
    if (!isEnabled(prefs)) return;
    await prefs.remove(widgetDatePrefsKey);
    await refreshWidgetIfStale();
  }

  /// GET-ward fetch of the daily quote (POST /api/v1/quote {action:today} —
  /// the same idempotent-per-day call the web toast uses; CSRF rides the
  /// persisted session's PHP sid via ApiClient.postJson).
  static Future<TodayQuote?> _fetchToday(ApiClient api) async {
    try {
      final data = await api.postJson('/api/v1/quote', {'action': 'today'});
      final q = data['quote'];
      if (q is! Map<String, dynamic>) return null;
      return TodayQuote(
        quote: QuoteData(
          id: (q['id'] ?? 0) is int
              ? q['id'] as int
              : int.tryParse((q['id'] ?? '').toString()) ?? 0,
          text: (q['text'] ?? '').toString(),
          author: (q['author'] ?? '').toString(),
          tags: (q['tags'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
        ),
        rated: (data['rated'] as String?)?.isNotEmpty == true
            ? data['rated'] as String
            : null,
        // The server's quote day — the truth for the freshness stamp.
        // Fall back to the device day only if the server ever omits it.
        date: (data['date'] as String?)?.isNotEmpty == true
            ? data['date'] as String
            : _todayKey(),
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

/// Top-level entry point for widget rate taps. Registered in the MAIN
/// isolate at app start (HomeWidget.registerInteractivityCallback needs a
/// stable handle); the actual call runs in a headless background isolate
/// spawned by home_widget's receiver. @pragma keeps it in the AOT snapshot.
@pragma('vm:entry-point')
Future<void> quoteWidgetRateCallback(Uri? uri) async {
  await DailyQuoteService.rateFromWidget(uri);
}
