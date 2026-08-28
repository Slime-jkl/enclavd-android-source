import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api/api_client.dart';
import 'daily_quote_widget.dart';

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

/// Today's quote, the user's rating (null = unrated) and the server's quote
/// day, which is what the widget freshness stamp must record.
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

class RateAction {
  const RateAction({required this.action, required this.quoteId});

  final String action; // 'like' | 'dislike'
  final int quoteId;
}

/// Daily quote notification + home-screen widget. The widget is the daily
/// surface when pinned, so no notification is shown in that case.
class DailyQuoteService {
  DailyQuoteService._();

  static const String taskName = 'enclavd-daily-quote';

  /// Widget rollover one-shot: fires ~10 min after UTC midnight,
  /// notification-free.
  static const String rolloverTaskName = 'enclavd-quote-rollover';

  static const String enabledPrefsKey = 'daily_quote_enabled';

  static const String widgetDatePrefsKey = 'daily_quote_widget_date';

  static const String widgetRateScheme = 'enclavdwidget';

  static const int _notificationId = 10001; // fixed id: one slot per day
  static const String _channelId = 'daily_quote';
  static const String _channelName = 'Daily quote';
  static const String _channelDescription = "Today's quote, once a day";

  // Delivery window: 08:00-20:00 local, 20:00 exclusive.
  static const int _windowStartHour = 8;
  static const int _windowLengthMinutes = 12 * 60; // 720 -> up to 19:59

  /// Buffer for device-clock skew; the server rotates at UTC midnight.
  static const int _rolloverOffsetMinutes = 10;

  /// Next delivery slot: a random minute in [08:00, 20:00), today if still
  /// ahead of [now], otherwise tomorrow.
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

  /// Next UTC midnight + 10 min; the server's day boundary is UTC.
  @visibleForTesting
  static DateTime nextMidnightFire(DateTime now) {
    final utc = now.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day)
        .add(const Duration(days: 1))
        .add(const Duration(minutes: _rolloverOffsetMinutes));
  }

  /// Parses a widget rate tap URI; null for foreign or malformed taps.
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

  /// Arms the next run. keep preserves an already-armed slot so app starts
  /// don't re-randomize it; nothing is pending after a completed run.
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
    await scheduleMidnightRun(); // the widget rollover rides along
  }

  /// Arms the widget rollover for ~10 min after the next UTC midnight.
  static Future<void> scheduleMidnightRun() async {
    final prefs = await SharedPreferences.getInstance();
    if (!isEnabled(prefs)) return;
    final now = DateTime.now();
    final fireAt = nextMidnightFire(now);
    final delay = fireAt.difference(now);
    await Workmanager().registerOneOffTask(
      rolloverTaskName,
      rolloverTaskName,
      initialDelay: delay,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
    debugPrint('daily quote: widget rollover in ${delay.inMinutes} min');
  }

  /// Cancels the armed runs (Settings toggle off).
  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(taskName);
    await Workmanager().cancelByUniqueName(rolloverTaskName);
    debugPrint('daily quote: cancelled');
  }

  /// Widget rollover run: pushes to the widget only when one is pinned;
  /// always re-arms tomorrow's boundary, success or not.
  static Future<void> runMidnightRollover() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!isEnabled(prefs)) return;
      if (!await _hasWidgetInstance()) {
        debugPrint('quote widget: rollover — no widget pinned, skipping');
        return;
      }
      final api = ApiClient(store: PrefsSessionStore(prefs));
      await api.restoreSession();
      if (!api.hasSession) {
        debugPrint('quote widget: rollover — no session, skipping');
        return;
      }
      final today = await _fetchToday(api);
      if (today == null) {
        debugPrint('quote widget: rollover — fetch failed');
        return;
      }
      if (prefs.getString(widgetDatePrefsKey) == today.date) {
        debugPrint(
            'quote widget: rollover — already fresh for ${today.date}');
        return;
      }
      await pushTodayToWidget(api: api, prefs: prefs, today: today);
    } finally {
      await scheduleMidnightRun(); // next boundary is armed regardless
    }
  }

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
      // The widget is the daily surface: skip the notification when one
      // is pinned, no double delivery.
      final widgetInUse = await _hasWidgetInstance();
      if (widgetInUse) {
        debugPrint('daily quote: widget present, notification skipped');
      } else {
        try {
          await plugin.show(
            id: _notificationId,
            title: '💬 Quote of the day',
            body: '“${today.quote.text}”\n— ${today.quote.author}',
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                _channelId,
                _channelName,
                channelDescription: _channelDescription,
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
                // The API serves the quote whole and it can run long; a
                // plain body collapses to ~2 lines in the shade with no
                // way to see the rest. BigTextStyle makes the notification
                // expandable so the FULL quote + author is always there.
                styleInformation: BigTextStyleInformation(
                  '“${today.quote.text}”\n— ${today.quote.author}',
                ),
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

    await scheduleNextRun(); // armed regardless; tomorrow retries
  }

  /// Probe failure defaults to false, so the notification still fires.
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

  /// Foreground widget refresh, once per local day. Silent and date-gated;
  /// call from app start/login.
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

  /// Widget rate-tap entry: posts the rating and re-renders the widget;
  /// re-syncs to the server's truth when the tap is rejected.
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
      return; // logged out; the widget can't rate. Next login re-pushes.
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
      // 400 'already rated' (double tap) or 'no current quote' (stale
      // widget); re-sync to today's state.
      debugPrint('quote widget: rate failed ($e) — resyncing');
      final today = await _fetchToday(api);
      if (today != null) {
        await pushTodayToWidget(api: api, prefs: prefs, today: today);
      }
    }
  }

  /// Writes today's quote to the widget and stamps the freshness date:
  /// the server's quote day, advanced only on a successful push.
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

  /// Fresh-session catch-up: drop the stamp and refetch right away.
  static Future<void> refreshWidgetNow() async {
    final prefs = await SharedPreferences.getInstance();
    if (!isEnabled(prefs)) return;
    await prefs.remove(widgetDatePrefsKey);
    await refreshWidgetIfStale();
  }

  /// POST /api/v1/quote {action: 'today'}, the same idempotent call the
  /// web toast uses.
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
        // The server's quote day; device day only as a fallback.
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

/// Widget rate-tap entry point, registered at app start.
@pragma('vm:entry-point')
Future<void> quoteWidgetRateCallback(Uri? uri) async {
  await DailyQuoteService.rateFromWidget(uri);
}
