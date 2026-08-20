import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:enclavd/screens/settings_screen.dart';
import 'package:enclavd/services/message_notifications.dart';
import 'package:enclavd/services/sound_service.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

void main() {
  setUp(() {
    SoundService.muted = true;
    MessageNotifications.instance = null;
  });
  tearDown(() => SoundService.muted = false);

  testWidgets('sound toggle flips SoundService.muted and persists',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      theme: buildEnclavdTheme(),
      home: const SettingsScreen(),
    ));
    await tester.pumpAndSettle();

    expect(SoundService.muted, isFalse, reason: 'sounds default ON');
    expect(find.byType(SwitchListTile), findsNWidgets(2),
        reason: 'sounds + message notifications');

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
}
