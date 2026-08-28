import 'package:flutter/services.dart';

/// Native foreground-service keep-alive (RealtimeKeepAliveService.kt).
///
/// While the app is minimized, Android suspends network access for
/// backgrounded apps (Doze / app standby / background-data restrictions):
/// the live SSE/WS streams die and every reconnect fails with a socket
/// error until the app returns to the foreground. MainActivity starts a
/// low-profile foreground service in onStop() and stops it in onStart(),
/// which holds the process in the "perceptible" state so the streams keep
/// their network - realtime notifications and messages while minimized.
/// This wrapper only exposes the Settings master toggle (stored natively).
class BackgroundKeepAlive {
  BackgroundKeepAlive._();

  static const MethodChannel _channel = MethodChannel('enclavd/keepalive');

  /// The master toggle; defaults to true on any host without the channel
  /// (tests, iOS) - the feature simply doesn't exist there.
  static Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? true;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
    } on MissingPluginException {
      // Non-Android host: nothing to toggle.
    }
  }
}
