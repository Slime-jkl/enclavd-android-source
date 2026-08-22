import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/services/push/push_registration_service.dart';
import 'package:enclavd/services/push/push_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PushManager.instance = null;
  });

  test('fallback label is the no-transport status text', () {
    expect(PushManager.fallbackLabel, '15-minute background checks');
    expect(PushManager.instance?.activeLabel, isNull); // unresolved yet
  });

  test('ensureResolved on a non-Android host keeps the polling fallback',
      () async {
    // flutter test runs on the host VM (not Android): resolution must
    // stop before any platform plugin is touched.
    await PushManager.ensureResolved(
      PushRegistrationService(() async => throw StateError('unused')),
    );

    expect(PushManager.instance, isNotNull);
    expect(PushManager.instance!.active, isNull);
    expect(PushManager.instance!.activeLabel, PushManager.fallbackLabel);
  });

  test('ensureResolved is idempotent and re-pushes the active token',
      () async {
    var registered = 0;
    final transport = _CountingTransport(onRegister: () => registered++);
    PushManager.instanceForTest(transport);

    await PushManager.ensureResolved(
      PushRegistrationService(() async => throw StateError('unused')),
    );
    await PushManager.ensureResolved(
      PushRegistrationService(() async => throw StateError('unused')),
    );

    expect(PushManager.instance!.active, same(transport));
    expect(registered, 2); // one re-push per ensureResolved call
  });

  test('syncFromPush completes with no singletons and no session', () async {
    // Background-isolate shape (app killed): no notification singletons,
    // no session → the worker-style run must no-op cleanly without
    // touching any platform channel.
    await syncFromPush();
  });
}

/// Test double: counts re-registrations without any platform plugin.
class _CountingTransport implements PushTransport {
  _CountingTransport({required this.onRegister});

  final void Function() onRegister;

  @override
  String get id => 'test';

  @override
  String get label => 'Test transport';

  @override
  Future<bool> init() async {
    onRegister();
    return true;
  }

  @override
  Future<void> registerToken() async => onRegister();
}
