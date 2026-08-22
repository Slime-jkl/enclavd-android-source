import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/services/push/push_registration_service.dart';

/// ApiClient with the network surgically replaced: the registration
/// service must never touch a real socket in tests.
class _FakeApiClient extends ApiClient {
  _FakeApiClient(
    SessionStore store, {
    this.hasSessionValue = true,
    this.failPost = false,
  }) : super(store: store);

  final bool hasSessionValue;
  final bool failPost;
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
    if (failPost) throw const ApiException('boom', status: 500);
    return {'success': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('register posts the transport + token when a session exists', () async {
    final client = _FakeApiClient(
      PrefsSessionStore(await SharedPreferences.getInstance()),
    );
    final service = PushRegistrationService(() async => client);

    await service.register(transport: 'fcm', token: 'tok123');

    expect(client.lastPath, '/api/v1/push');
    expect(client.lastBody, {
      'action': 'register',
      'transport': 'fcm',
      'token': 'tok123',
      'platform': 'android',
    });
  });

  test('register skips without a session (cold start before login)', () async {
    final client = _FakeApiClient(
      PrefsSessionStore(await SharedPreferences.getInstance()),
      hasSessionValue: false,
    );
    final service = PushRegistrationService(() async => client);

    await service.register(
      transport: 'unifiedpush',
      token: 'https://push.example/abc',
    );

    expect(client.lastPath, isNull); // nothing sent, nothing thrown
  });

  test('register swallows server failures (endpoint not deployed yet)', () async {
    final client = _FakeApiClient(
      PrefsSessionStore(await SharedPreferences.getInstance()),
      failPost: true,
    );
    final service = PushRegistrationService(() async => client);

    await service.register(transport: 'fcm', token: 'tok'); // must not throw
    expect(client.lastPath, '/api/v1/push');
  });

  test('unregister posts the token drop', () async {
    final client = _FakeApiClient(
      PrefsSessionStore(await SharedPreferences.getInstance()),
    );
    final service = PushRegistrationService(() async => client);

    await service.unregister(transport: 'fcm', token: 'tok');

    expect(client.lastPath, '/api/v1/push');
    expect(client.lastBody, {
      'action': 'unregister',
      'transport': 'fcm',
      'token': 'tok',
    });
  });
}
