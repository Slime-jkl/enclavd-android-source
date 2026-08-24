import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enclavd/screens/settings_screen.dart';
import 'package:enclavd/services/message_notifications.dart';
import 'package:enclavd/services/social_notifications.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

/// Minimal notifier fake for the settings screen (the OS permission state
/// is what the warning row reads; nothing else is exercised here).
class _SettingsFakeNotifier implements LocalNotifier {
  bool osEnabled = true;
  int openSettingsCalls = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermission() async {}

  @override
  Future<bool> areNotificationsEnabled() async => osEnabled;

  @override
  Future<bool> openAppNotificationSettings() async {
    openSettingsCalls++;
    return true;
  }

  @override
  Future<void> showMessageNotification({
    required int notificationId,
    required String senderName,
    required String message,
    required int conversationId,
    String? avatarPath,
  }) async {}

  @override
  Future<void> showSocialNotification({
    required int notificationId,
    required String title,
    required String body,
  }) async {}
}

MessageNotifications _withNotifier(_SettingsFakeNotifier notifier) =>
    MessageNotifications(
      notifier: notifier,
      messagesFactory: () async =>
          throw StateError('not used in settings tests'),
    );

void main() {
  setUp(() {
    SoundService.muted = true;
    MessageNotifications.instance = null;
    // The settings screen reads the keep-alive toggle over the native
    // channel on load. Unhandled platform channels HANG in widget tests
    // (no platform side to reply), so every test gets a default handler;
    // the dedicated keep-alive test overrides it with a stateful one.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('enclavd/keepalive'),
      (call) async => call.method == 'isEnabled' ? true : null,
    );
    // Same for home_widget: the daily-quote widget display prefs are read
    // on load (and written on toggle). A null response = defaults, which
    // is exactly what the screen needs in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('home_widget'),
      (call) async => null,
    );
  });
  tearDown(() {
    SoundService.muted = false;
    MessageNotifications.instance = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('enclavd/keepalive'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
  });

  testWidgets('sound toggle flips SoundService.muted and persists',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    // Tall viewport so the lazy ListView builds ALL toggles (the screen
    // now has 4 — the daily-quote options moved to their own screen).
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(SoundService.muted, isFalse, reason: 'sounds default ON');
    expect(find.byType(SwitchListTile), findsNWidgets(4),
        reason: 'sounds + message notifications + notification alerts '
            '+ live updates while minimized');

    // Turn sounds off.
    await tester.tap(find.widgetWithText(SwitchListTile, 'Sound effects'));
    await tester.pumpAndSettle();
    expect(SoundService.muted, isTrue);

    // Persisted: a fresh screen load honors the stored value.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sounds_enabled'), isFalse);

    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();
    expect(SoundService.muted, isTrue, reason: 'restored from prefs');
  });

  testWidgets('message notifications toggle persists and defaults ON',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Message notifications'))
            .value,
        isTrue,
        reason: 'notifications default ON');

    // Turn them off.
    await tester
        .tap(find.widgetWithText(SwitchListTile, 'Message notifications'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(MessageNotifications.enabledPrefsKey), isFalse);

    // Fresh screen load restores the off state.
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Message notifications'))
            .value,
        isFalse,
        reason: 'restored from prefs');
  });

  testWidgets('notification alerts toggle persists and defaults ON',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Notification alerts'))
            .value,
        isTrue,
        reason: 'alerts default ON');

    // Turn them off.
    await tester
        .tap(find.widgetWithText(SwitchListTile, 'Notification alerts'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SocialNotifications.enabledPrefsKey), isFalse);

    // Fresh screen load restores the off state.
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, 'Notification alerts'))
            .value,
        isFalse,
        reason: 'restored from prefs');
  });

  testWidgets('live-updates-while-minimized toggle defaults ON and flips '
      'via the native channel', (tester) async {
    const channel = MethodChannel('enclavd/keepalive');
    final calls = <MethodCall>[];
    var nativeEnabled = true; // the native side's stored state
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'isEnabled':
          return nativeEnabled;
        case 'setEnabled':
          nativeEnabled = call.arguments['enabled'] as bool;
          return null;
      }
      return null;
    });

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();

    // The keep-alive tile is the last toggle — scroll it into view first
    // (the lazy ListView doesn't build items below the fold).
    await tester.scrollUntilVisible(
        find.text('Live updates while minimized'), 200);

    expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(
                SwitchListTile, 'Live updates while minimized'))
            .value,
        isTrue,
        reason: 'keep-alive defaults ON');

    await tester.tap(find.widgetWithText(
        SwitchListTile, 'Live updates while minimized'));
    await tester.pumpAndSettle();

    final setCalls =
        calls.where((c) => c.method == 'setEnabled').toList();
    expect(setCalls.length, 1, reason: 'one flip -> one native call');
    expect(setCalls.single.arguments, {'enabled': false});

    // The toggle state is native-owned: a fresh screen load reads it back.
    calls.clear();
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Live updates while minimized'), 200);
    expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(
                SwitchListTile, 'Live updates while minimized'))
            .value,
        isFalse,
        reason: 'reads the native-side state on load');
  });

  testWidgets('OS-blocked notifications show the warning row', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final notifier = _SettingsFakeNotifier()..osEnabled = false;
    MessageNotifications.instance = _withNotifier(notifier);

    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();

    // The warning row is the last ListView item — with four toggles above
    // it, scroll it into view before asserting.
    await tester.scrollUntilVisible(
        find.text('Notifications are blocked on this phone'), 200);

    expect(find.text('Notifications are blocked on this phone'),
        findsOneWidget,
        reason: 'toggle ON but the OS denies → the warning must be visible');
    expect(find.text('Open settings'), findsOneWidget);

    await tester.ensureVisible(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(notifier.openSettingsCalls, 1,
        reason: 'button deep-links into the OS notification settings');
  });

  testWidgets('no warning when the OS allows notifications', (tester) async {
    SharedPreferences.setMockInitialValues({});
    MessageNotifications.instance = _withNotifier(_SettingsFakeNotifier());

    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Notifications are blocked on this phone'),
        findsNothing);
  });

  testWidgets('no warning when the user opted out (toggle OFF)',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {MessageNotifications.enabledPrefsKey: false});
    final notifier = _SettingsFakeNotifier()..osEnabled = false;
    MessageNotifications.instance = _withNotifier(notifier);

    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Notifications are blocked on this phone'),
        findsNothing,
        reason: 'opt-out is intentional — no nagging');
  });
}
