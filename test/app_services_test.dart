import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/main.dart';
import 'package:enclavd/services/message_notifications.dart';
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
