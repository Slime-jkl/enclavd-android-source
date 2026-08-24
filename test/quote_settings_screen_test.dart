import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import 'package:enclavd/screens/quote_help_screen.dart';
import 'package:enclavd/screens/quote_settings_screen.dart';
import 'package:enclavd/services/daily_quote_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

/// Records WorkManager arming/cancelling (the master toggle's effect)
/// without touching platform channels.
class _FakeWorkmanager extends WorkmanagerPlatform {
  int armed = 0;
  int cancelled = 0;

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
    armed++;
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    cancelled++;
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

  testWidgets('shows the feature toggles + the TLDR help link',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const QuoteSettingsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Daily quote'), findsOneWidget);
    expect(find.text('Show tags'), findsOneWidget);
    expect(find.text('Light variant'), findsOneWidget);
    // No logo toggle — the logo is always on by design.
    expect(find.text('Show logo'), findsNothing);
    expect(find.text('How daily quotes work'), findsOneWidget);
    expect(find.textContaining('always shown on the widget'), findsOneWidget);

    // Defaults: daily quote ON, tags ON, light OFF.
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
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Light variant'))
            .value,
        isFalse);
  });

  testWidgets('master toggle arms and cancels the daily-quote pipeline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Construct the Workmanager singleton FIRST (in the Linux test env it
    // binds the Linux impl), then swap in the recording fake — the impl
    // reads WorkmanagerPlatform.instance live at call time.
    Workmanager().setPluginRegistrant((_) {});
    final wm = _FakeWorkmanager();
    WorkmanagerPlatform.instance = wm;

    await tester.pumpWidget(wrap(const QuoteSettingsScreen()));
    await tester.pumpAndSettle();

    // Off → cancels the armed run.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Daily quote'));
    await tester.pumpAndSettle();
    expect(wm.cancelled, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(DailyQuoteService.enabledPrefsKey), isFalse);

    // On again → re-arms.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Daily quote'));
    await tester.pumpAndSettle();
    expect(wm.armed, 1);
    expect(prefs.getBool(DailyQuoteService.enabledPrefsKey), isTrue);
  });

  testWidgets('widget display toggles persist to widget storage',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
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
    await tester.tap(find.widgetWithText(SwitchListTile, 'Light variant'));
    await tester.pumpAndSettle();

    final saved = calls
        .where((c) => c.method == 'saveWidgetData')
        .map((c) => c.arguments)
        .toList();
    expect(
        saved.any((a) =>
            a is Map && a['key'] == 'widget_show_tags' && a['value'] == false),
        isTrue,
        reason: 'tags toggle persists false');
    expect(
        saved.any((a) =>
            a is Map && a['key'] == 'widget_light' && a['value'] == true),
        isTrue,
        reason: 'light toggle persists true');
    expect(
        saved.any((a) => a is Map && a['key'] == 'widget_show_logo'),
        isFalse,
        reason: 'no logo key is ever written (logo always on)');
  });

  testWidgets('help link opens the TLDR page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(wrap(const QuoteSettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('How daily quotes work'));
    await tester.pumpAndSettle();
    expect(find.byType(QuoteHelpScreen), findsOneWidget);
  });
}
