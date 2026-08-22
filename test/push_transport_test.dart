import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/services/push/push_registration_service.dart';
import 'package:enclavd/services/push/push_transport.dart';
import 'package:enclavd/services/push/unified_push_transport.dart';

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

  test('UP registerToken replays the persisted endpoint after login',
      () async {
    // Cold start before login: the distributor delivers the endpoint,
    // the server-side register is skipped (no session) — but the endpoint
    // is persisted. After login, ensureResolved → registerToken must
    // re-post it so the server learns the device.
    SharedPreferences.setMockInitialValues({
      UnifiedPushTransport.endpointPrefsKey: 'https://ntfy.sh/abc123',
    });
    final client = _FakeApiClient(
      PrefsSessionStore(await SharedPreferences.getInstance()),
    );
    final transport = UnifiedPushTransport(
      registration: PushRegistrationService(() async => client),
      onSync: () async {},
    );

    await transport.registerToken();

    expect(client.lastPath, '/api/v1/push');
    expect(client.lastBody, {
      'action': 'register',
      'transport': 'unifiedpush',
      'token': 'https://ntfy.sh/abc123',
      'platform': 'android',
    });
  });

  test('UP registerToken no-ops when no endpoint was ever delivered',
      () async {
    // First start with no distributor yet: nothing stored, nothing to
    // register — must not touch the network.
    final client = _FakeApiClient(
      PrefsSessionStore(await SharedPreferences.getInstance()),
    );
    final transport = UnifiedPushTransport(
      registration: PushRegistrationService(() async => client),
      onSync: () async {},
    );

    await transport.registerToken();

    expect(client.lastPath, isNull);
  });

  test('UP registerToken skips without a session (replay waits for login)',
      () async {
    SharedPreferences.setMockInitialValues({
      UnifiedPushTransport.endpointPrefsKey: 'https://ntfy.sh/abc123',
    });
    final client = _FakeApiClient(
      PrefsSessionStore(await SharedPreferences.getInstance()),
      hasSessionValue: false,
    );
    final transport = UnifiedPushTransport(
      registration: PushRegistrationService(() async => client),
      onSync: () async {},
    );

    await transport.registerToken();

    expect(client.lastPath, isNull); // registration service's own guard
  });
}

/// ApiClient with the network surgically replaced (mirrors the fake in
/// push_registration_service_test.dart).
class _FakeApiClient extends ApiClient {
  _FakeApiClient(SessionStore store, {this.hasSessionValue = true})
      : super(store: store);

  final bool hasSessionValue;
  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  bool get hasSession => hasSessionValue;

  @override
  Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    lastPath = path;
    lastBody = body;
    return {'success': true};
  }
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
