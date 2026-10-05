import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// Wordmark the site is currently serving, e.g. seasonal art. Null means
/// the app keeps its own bundled mark.
class BrandingService {
  BrandingService._();

  static final BrandingService instance = BrandingService._();

  /// Dark-background wordmark path.
  final ValueNotifier<String?> wordmark = ValueNotifier<String?>(null);

  /// Dark-ink variant for light backgrounds; null until the site ships one.
  final ValueNotifier<String?> wordmarkLight = ValueNotifier<String?>(null);

  void update({String? dark, String? light}) {
    wordmark.value = dark;
    wordmarkLight.value = light;
  }

  /// Site-relative paths resolve against the host this build talks to.
  static String? resolveUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${AppConfig.apiBaseUrl}$path';
  }
}
