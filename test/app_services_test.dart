import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/main.dart';
import 'package:enclavd/services/message_notification_source.dart';
import 'package:enclavd/services/message_notifications.dart';
import 'package:enclavd/services/social_notification_source.dart';
import 'package:enclavd/services/social_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MessageNotifications.instance = null;
    SocialNotifications.instance = null;
    AppServices.current = null;
  });

  tearDown(() {
    MessageNotifications.instance = null;
    SocialNotifications.instance = null;
    AppServices.current = null;
  });

  test('create() sets the current container to the LATEST one', () async {
    final first = await AppServices.create();
    expect(AppServices.current, same(first));

    final second = await AppServices.create();
    expect(AppServices.current, same(second),
        reason: 'the app uses the latest container after a re-create');
  });

  test('the notification singleton is created once and reused', () async {
    final first = await AppServices.create();
    final singleton = first.messageAlerts;

    final second = await AppServices.create();
    expect(second.messageAlerts, same(singleton),
        reason: 'first create wins — plugin initialized exactly once');
    expect(MessageNotifications.instance, same(singleton));
  });

  test('create() resets the worker quiet-window flags at boot', () async {
    // A process killed while the messages screen or the notification drawer
    // was open leaves the prefs flags true — the worker would stay silent
    // for messages AND notifications until the next visit. Boot must clear.
    SharedPreferences.setMockInitialValues({
      MessageNotificationSource.chatOpenPrefsKey: true,
      SocialNotificationSource.drawerOpenPrefsKey: true,
    });
    await AppServices.create();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(MessageNotificationSource.chatOpenPrefsKey), isFalse,
        reason: 'chat-open quiet window must not survive a kill');
    expect(prefs.getBool(SocialNotificationSource.drawerOpenPrefsKey), isFalse,
        reason: 'drawer-open quiet window must not survive a kill');
  });

  test('the social notifications singleton is created once and reused',
      () async {
    await AppServices.create();
    final singleton = SocialNotifications.instance;
    expect(singleton, isNotNull);

    await AppServices.create();
    expect(SocialNotifications.instance, same(singleton),
        reason: 'first create wins — one social path per app lifetime');
  });
}
