import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/main.dart';
import 'package:enclavd/services/message_notifications.dart';
import 'package:enclavd/services/notification_taps.dart';
import 'package:enclavd/services/social_notifications.dart';

class _FakeNotifier implements LocalNotifier {
  _FakeNotifier({this.launch});

  final String? launch;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermission() async {}

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<bool> openAppNotificationSettings() async => true;

  @override
  Future<void> cancelNotification(int notificationId) async {}

  @override
  Future<String?> launchPayload() async => launch;

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
    required String payload,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppServices services;

  setUpAll(() async {
    // Real container: the routing only needs AppServices.current to be set,
    // and its construction uses no sockets with an empty session.
    SharedPreferences.setMockInitialValues({});
    services = await AppServices.create();
  });

  setUp(() {
    AppServices.current = null;
    // Inert stand-ins: the real screens load over the network on build.
    NotificationTaps.drawerBuilder = (_) => const Text('drawer');
    NotificationTaps.messagesBuilder = () => const Text('inbox');
    NotificationTaps.attach(_FakeNotifier());
    QuoteDeepLink.consume();
  });

  tearDown(() {
    AppServices.current = null;
    MessageNotifications.instance = null;
    SocialNotifications.instance = null;
  });

  Future<void> pumpShell(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('home')),
        ),
      );

  testWidgets('a social alert tap opens the notification drawer',
      (tester) async {
    AppServices.current = services;
    await pumpShell(tester);

    NotificationTaps.handleTap('n:12');
    await tester.pumpAndSettle();

    expect(find.text('drawer'), findsOneWidget);
    expect(find.text('home'), findsNothing);
  });

  testWidgets('a message tap opens the inbox', (tester) async {
    await pumpShell(tester);

    NotificationTaps.handleTap('c:5');
    await tester.pumpAndSettle();

    expect(find.text('inbox'), findsOneWidget);
  });

  testWidgets('the live callback routes a tap and ignores a swipe',
      (tester) async {
    AppServices.current = services;
    await pumpShell(tester);

    NotificationTaps.handleResponse(const NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      payload: 'n:12',
    ));
    await tester.pumpAndSettle();
    expect(find.text('drawer'), findsOneWidget);

    // A dismissal arrives here too (main isolate may see it); it must not
    // push anything.
    NotificationTaps.handleResponse(const NotificationResponse(
      notificationResponseType: NotificationResponseType.notificationDismissed,
      payload: 'n:12',
    ));
    await tester.pumpAndSettle();
    expect(find.text('drawer'), findsOneWidget);
  });

  testWidgets('a tap with no session waits for the gate', (tester) async {
    // Cold start: the tap is read back after login, when the drawer has
    // the session it needs.
    NotificationTaps.handleTap('n:12');
    await pumpShell(tester);
    expect(find.text('drawer'), findsNothing, reason: 'no session yet');

    AppServices.current = services;
    await NotificationTaps.resolvePending();
    await tester.pumpAndSettle();
    expect(find.text('drawer'), findsOneWidget);
  });

  testWidgets('a tap that cold-started the app lands after the gate',
      (tester) async {
    AppServices.current = services;
    NotificationTaps.attach(_FakeNotifier(launch: 'c:9'));
    await pumpShell(tester);

    await NotificationTaps.resolvePending();
    await tester.pumpAndSettle();

    expect(find.text('inbox'), findsOneWidget);
  });

  testWidgets('a payload that is not a notification routes nowhere',
      (tester) async {
    AppServices.current = services;
    await pumpShell(tester);

    NotificationTaps.handleTap('');
    NotificationTaps.handleTap('something-else');
    await tester.pumpAndSettle();

    expect(find.text('drawer'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  test('the quote notification still deep-links', () {
    // Parked for the gate, exactly like the daily-quote widget tap.
    NotificationTaps.handleTap('quote');
    expect(QuoteDeepLink.pending, isTrue);
  });
}
