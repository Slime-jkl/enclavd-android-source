// Push transport selection indirection — the repo's flavor switch.
//
// play/dev builds compile the real FCM transport (this default export).
// The F-Droid flow runs tool/strip_firebase.py BEFORE `flutter pub get`,
// which rewires this file to export the firebase-free stub
// (fcm_transport_stub.dart) AND strips firebase_core / firebase_messaging
// from pubspec.yaml — so the fdroid dependency graph and resolved pub cache
// contain ZERO Google code. Never import fcm_transport.dart directly; go
// through this file.
export 'fcm_transport.dart';
