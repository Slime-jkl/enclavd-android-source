import 'push_registration_service.dart';
import 'push_transport.dart';

/// Compile-only stand-in for the FCM transport on the F-Droid flavor.
///
/// tool/strip_firebase.py rewires transport_selector.dart to export this
/// stub while pubspec.yaml is stripped of firebase_core/firebase_messaging,
/// so the fdroid build never resolves or compiles the Google packages.
/// PushManager's const gates (AppConfig.enableFcm == false) make sure
/// nothing here ever runs — this class exists only to keep
/// push_transport.dart compiling on that flavor.
class FcmTransport implements PushTransport {
  FcmTransport({required this.registration, required this.onSync});

  final PushRegistrationService registration;
  final Future<void> Function() onSync;

  static void bindBackgroundHandler() {}

  @override
  String get id => 'fcm';

  @override
  String get label => 'FCM push';

  @override
  Future<bool> init() async => false;

  @override
  Future<void> registerToken() async {}
}
