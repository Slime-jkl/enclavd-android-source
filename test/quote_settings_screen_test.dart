import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:enclavd/screens/quote_help_screen.dart';
import 'package:enclavd/screens/quote_settings_screen.dart';
import 'package:enclavd/services/daily_quote_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/quote_widget_preview.dart';

class _FakeWorkmanager extends WorkmanagerPlatform {
  final List<String> armed = [];
  final List<String> cancelled = [];

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {
    armed.add(uniqueName);
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelled.add(uniqueName);
  }
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async => null,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
  });

  Widget wrap(Widget child) => MaterialApp(
        theme: buildEnclavdTheme(),
        home: child,
      );

  /// Serves widget-storage reads from [data]; anything unlisted reads null.
  void mockWidgetData(Map<String, dynamic> data) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), (call) async {
      if (call.method == 'getWidgetData') {
        final args = call.arguments as Map;
        return data[args['id']] as Object?;
      }
      return null;
    });
  }

  /// The preview pushes the toggles below the default 600px viewport.
  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows the feature toggles + the TLDR help link',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tallView(tester);
    await tester.pumpWidget(wrap(const QuoteSettingsScreen()));
    await tester.pumpAndSettle();

    expect(
        find.widgetWithText(SwitchListTile, 'Daily quote'), findsOneWidget,
        reason: 'the section label also reads "Daily quote" - scope to the '
            'toggle');
    expect(find.widgetWithText(SwitchListTile, 'Show tags'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Follow system theme'),
        findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Light variant'),
        findsOneWidget);
    expect(find.text('Show logo'), findsNothing);
    expect(find.text('How daily quotes work'), findsOneWidget);
    expect(find.textContaining('always shown on the widget'), findsOneWidget);

    // Defaults: daily quote ON, tags ON, follow-system ON, light OFF.
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Daily quote'))
            .value,
        isTrue);
    expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Show tags'))
            .value,
        isTrue);
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Follow system theme'))
            .value,
        isTrue);
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Light variant'))
            .onChanged,
        isNull,
        reason: 'manual light/dark is locked while following the system theme');
    expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Light variant'))
            .value,
        isFalse);
  });

  testWidgets('master toggle arms and cancels the daily-quote pipeline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tallView(tester);
    // Bind the Workmanager singleton first (Linux test env), then swap in
    // the recording fake: the impl reads WorkmanagerPlatform.instance live.
    Workmanager();
    final wm = _FakeWorkmanager();
    WorkmanagerPlatform.instance = wm;

    await tester.pumpWidget(wrap(const QuoteSettingsScreen()));
    await tester.pumpAndSettle();

    // Off -> cancels BOTH unique names: the random slot and the rollover.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Daily quote'));
    await tester.pumpAndSettle();
    expect(wm.cancelled, contains(DailyQuoteService.taskName));
    expect(wm.cancelled, contains(DailyQuoteService.rolloverTaskName));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DailyQuoteService.enabledPrefsKey), isFalse);

    // On again -> re-arms both.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Daily quote'));
    await tester.pumpAndSettle();
    expect(wm.armed, contains(DailyQuoteService.taskName));
    expect(wm.armed, contains(DailyQuoteService.rolloverTaskName));
    expect(prefs.getBool(DailyQuoteService.enabledPrefsKey), isTrue);
  });

  testWidgets('widget display toggles persist to widget storage',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tallView(tester);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), (call) {
      calls.add(call);
      return null;
    });

    await tester.pumpWidget(wrap(const QuoteSettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Show tags'));
    await tester.pumpAndSettle();
    // The manual Light variant is greyed out while the widget follows the system theme.
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Light variant'))
            .onChanged,
        isNull,
        reason: 'manual light/dark is disabled while following the system theme');
    await tester.tap(find.widgetWithText(SwitchListTile, 'Follow system theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Light variant'));
    await tester.pumpAndSettle();

    final saved = calls
        .where((c) => c.method == 'saveWidgetData')
        .map((c) => c.arguments)
        .toList();
    expect(
        saved.any((a) =>
            a is Map && a['id'] == 'widget_show_tags' && a['data'] == false),
        isTrue,
        reason: 'tags toggle persists false');
    expect(
        saved.any((a) =>
            a is Map && a['id'] == 'widget_follow_system' && a['data'] == false),
        isTrue,
        reason: 'follow-system toggle persists false');
    expect(
        saved.any((a) =>
            a is Map && a['id'] == 'widget_light' && a['data'] == true),
        isTrue,
        reason: 'light toggle persists true once the manual override unlocks');
    expect(
        saved.any((a) => a is Map && a['id'] == 'widget_show_logo'),
        isFalse,
        reason: 'no logo key is ever written (logo always on)');
  });

  testWidgets('help link opens the TLDR page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tallView(tester);
    await tester.pumpWidget(wrap(const QuoteSettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('How daily quotes work'));
    await tester.pumpAndSettle();
    expect(find.byType(QuoteHelpScreen), findsOneWidget);
  });

  testWidgets('preview shows the quote currently on the widget',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tallView(tester);
    mockWidgetData({
      'quote_text': 'A real quote.',
      'quote_author': 'Someone',
      'quote_tags': 'wisdom|life',
      'quote_id': '7',
      'quote_rated': '',
      'widget_show_tags': true,
      'widget_light': false,
      'widget_follow_system': true,
    });
    await tester.pumpWidget(wrap(const QuoteSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('A real quote.'), findsOneWidget);
    expect(find.text('- Someone'), findsOneWidget);
    expect(find.text('\u201C'), findsOneWidget);
    expect(find.text('\u201D'), findsOneWidget);
    expect(find.textContaining('#wisdom', findRichText: true), findsOneWidget);
    expect(find.textContaining('#life', findRichText: true), findsOneWidget);
    expect(
        find.textContaining("Open Enclavd to see today's quote"), findsNothing);
  });

  testWidgets('preview falls back to the empty state when nothing is pushed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tallView(tester);
    await tester.pumpWidget(wrap(const QuoteSettingsScreen()));
    await tester.pumpAndSettle();

    expect(
        find.textContaining("Open Enclavd to see today's quote"), findsOneWidget);
    expect(find.text('\u201C'), findsNothing);
    expect(find.text('\u201D'), findsNothing);
    expect(find.text('- Someone'), findsNothing);
  });

  testWidgets('show tags toggle updates the preview in real time',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tallView(tester);
    mockWidgetData({
      'quote_text': 'A real quote.',
      'quote_author': 'Someone',
      'quote_tags': 'wisdom',
      'quote_id': '7',
      'quote_rated': '',
      'widget_show_tags': true,
      'widget_light': false,
      'widget_follow_system': true,
    });
    await tester.pumpWidget(wrap(const QuoteSettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('#wisdom', findRichText: true), findsOneWidget);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Show tags'));
    await tester.pumpAndSettle();
    expect(find.textContaining('#wisdom', findRichText: true), findsNothing);
  });

  testWidgets('theme toggles flip the preview light/dark in real time',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    SharedPreferences.setMockInitialValues({});
    tallView(tester);
    mockWidgetData({
      'quote_text': 'A real quote.',
      'quote_author': 'Someone',
      'quote_tags': '',
      'quote_id': '7',
      'quote_rated': '',
      'widget_show_tags': true,
      'widget_light': false,
      'widget_follow_system': true,
    });
    await tester.pumpWidget(wrap(const QuoteSettingsScreen()));
    await tester.pumpAndSettle();

    QuoteWidgetPreview preview() =>
        tester.widget<QuoteWidgetPreview>(find.byType(QuoteWidgetPreview));
    // Test env is light and the preview follows the system by default.
    expect(preview().light, isTrue);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Follow system theme'));
    await tester.pumpAndSettle();
    expect(preview().light, isFalse);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Light variant'));
    await tester.pumpAndSettle();
    expect(preview().light, isTrue);
  });
}
