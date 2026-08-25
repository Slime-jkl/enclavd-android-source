import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/services/daily_quote_service.dart';
import 'package:enclavd/services/daily_quote_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DailyQuoteService.nextSlot', () {
    test('always lands in [06:00, 20:00) local, today or tomorrow', () {
      final rng = Random(42);
      for (var i = 0; i < 300; i++) {
        final now = DateTime(2026, 8, 24, rng.nextInt(24), rng.nextInt(60),
            rng.nextInt(60));
        final slot = DailyQuoteService.nextSlot(now, random: rng);
        expect(slot.hour, inInclusiveRange(6, 19),
            reason: 'slot outside the 06:00-20:00 window for now=$now');
        expect(slot.minute, inInclusiveRange(0, 59));
        expect(slot.second, 0, reason: 'slot must be on a whole minute');

        final sameLocalDay = slot.year == now.year &&
            slot.month == now.month &&
            slot.day == now.day;
        final nextLocalDay = slot.difference(
                DateTime(now.year, now.month, now.day))
            .inDays ==
            1;
        expect(sameLocalDay || nextLocalDay, isTrue,
            reason: 'slot must be today or tomorrow, got $slot for now=$now');
      }
    });

    test('uses today when the slot is still ahead, tomorrow when past', () {
      final rng = Random(7);

      // 05:00 — every candidate (>= 06:00 today) is still ahead → today.
      final early = DateTime(2026, 8, 24, 5);
      final s1 = DailyQuoteService.nextSlot(early, random: rng);
      expect(DateTime(s1.year, s1.month, s1.day),
          DateTime(early.year, early.month, early.day));

      // 23:00 — every candidate is already past → tomorrow (month-safe).
      final late = DateTime(2026, 8, 31, 23);
      final s2 = DailyQuoteService.nextSlot(late, random: rng);
      expect(DateTime(s2.year, s2.month, s2.day),
          DateTime(late.year, late.month, late.day)
              .add(const Duration(days: 1)));
    });

    test('a fixed RNG yields a deterministic slot (seed stability)', () {
      final a = DailyQuoteService.nextSlot(DateTime(2026, 8, 24, 10),
          random: Random(1234));
      final b = DailyQuoteService.nextSlot(DateTime(2026, 8, 24, 10),
          random: Random(1234));
      expect(a, b);
    });
  });

  group('DailyQuoteService.parseRateAction', () {
    test('parses like/dislike taps carrying a quote id', () {
      final like = DailyQuoteService.parseRateAction(
          Uri.parse('enclavdwidget://like?id=983'));
      expect(like?.action, 'like');
      expect(like?.quoteId, 983);
      final dislike = DailyQuoteService.parseRateAction(
          Uri.parse('enclavdwidget://dislike?id=12'));
      expect(dislike?.action, 'dislike');
      expect(dislike?.quoteId, 12);
    });

    test('rejects null, foreign hosts and malformed ids', () {
      expect(DailyQuoteService.parseRateAction(null), isNull);
      expect(
          DailyQuoteService.parseRateAction(
              Uri.parse('enclavdwidget://other?id=983')),
          isNull);
      expect(
          DailyQuoteService.parseRateAction(
              Uri.parse('https://enclavd.com/like?id=1')),
          isNull);
      expect(
          DailyQuoteService.parseRateAction(
              Uri.parse('enclavdwidget://like?id=abc')),
          isNull);
      expect(
          DailyQuoteService.parseRateAction(
              Uri.parse('enclavdwidget://like')),
          isNull);
      expect(
          DailyQuoteService.parseRateAction(
              Uri.parse('enclavdwidget://like?id=0')),
          isNull);
      expect(
          DailyQuoteService.parseRateAction(
              Uri.parse('enclavdwidget://dislike?id=-5')),
          isNull);
    });
  });

  group('DailyQuoteService defaults', () {
    test('the feature is enabled by default', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(DailyQuoteService.isEnabled(prefs), isTrue);
    });
  });

  group('DailyQuoteService freshness stamp', () {
    const channel = MethodChannel('home_widget');

    TodayQuote quoteFor(String serverDate) => TodayQuote(
          quote: const QuoteData(
              id: 42, text: 't', author: 'a', tags: ['x']),
          rated: null,
          date: serverDate,
        );

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
        'stamps the SERVER quote day on a successful push, not the '
        'device day', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => true);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Server day deliberately far from the real date (2026-08-25).
      await DailyQuoteService.pushTodayToWidget(
        api: ApiClient(store: PrefsSessionStore(prefs)),
        prefs: prefs,
        today: quoteFor('2026-01-02'),
      );

      expect(prefs.getString(DailyQuoteService.widgetDatePrefsKey),
          '2026-01-02');
    });

    test('does NOT stamp when the widget push fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel,
              (call) async => throw PlatformException(code: 'boom'));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final ok = await DailyQuoteWidget.push(
        text: 't',
        author: 'a',
        tags: const ['x'],
        quoteId: 42,
      );
      expect(ok, isFalse);

      await DailyQuoteService.pushTodayToWidget(
        api: ApiClient(store: PrefsSessionStore(prefs)),
        prefs: prefs,
        today: quoteFor('2026-08-25'),
      );

      expect(prefs.getString(DailyQuoteService.widgetDatePrefsKey), isNull);
    });

    test('refreshWidgetNow clears a blocking stamp even when the fetch '
        'fails (no network in tests)', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => true);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(DailyQuoteService.widgetDatePrefsKey, '2026-08-24');

      await DailyQuoteService.refreshWidgetNow();

      // The fetch cannot succeed here (flutter_test mocks HttpClient to
      // 400) — the important guarantee is that the blocking stamp is gone,
      // so the NEXT app start retries instead of trusting it.
      expect(prefs.getString(DailyQuoteService.widgetDatePrefsKey), isNull);
    });
  });
}
