import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/main.dart';
import 'package:enclavd/services/message_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MessageNotifications.instance = null;
    AppServices.current = null;
  });

  tearDown(() {
    MessageNotifications.instance = null;
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
    final singleton = first.notifications;

    final second = await AppServices.create();
    expect(second.notifications, same(singleton),
        reason: 'first create wins — plugin initialized exactly once');
    expect(MessageNotifications.instance, same(singleton));
  });
}
