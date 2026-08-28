import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

/// Resolves a sender's avatar to a LOCAL cached file so Android can render
/// it as the MessagingStyle bubble icon (notification persons cannot load
/// remote images - the icon must be a file or drawable). Downloads on
/// cache miss, reuses for 24h (a day-old file is fresh enough for a
/// notification), returns null on ANY failure - the notification still
/// shows with the initial-letter placeholder. Never throws. Shared by the
/// live path and the background worker.
Future<String?> resolveNotificationAvatar(
  String avatarPath, {
  String? baseUrl,
  Directory? cacheDir,
}) async {
  try {
    final root = cacheDir ?? await getApplicationCacheDirectory();
    final dir = Directory('${root.path}/avatars');
    await dir.create(recursive: true);

    // Sanitize the path into a stable filename (avatars are unique per
    // user in practice - the path IS the cache key).
    final safe = avatarPath.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}/$safe');

    if (await file.exists() && await file.length() > 0) {
      final age = DateTime.now().difference(await file.lastModified());
      if (age < const Duration(hours: 24)) {
        // Re-validate the CACHED file, not just the fresh download: a
        // partially-written file (process killed mid-write) decodes fine
        // by length but breaks plugin.show's bitmap decode - which would
        // kill EVERY message notification for the rest of the TTL.
        // Invalid cached files are deleted and re-downloaded below.
        try {
          final codec = await ui
              .instantiateImageCodec(await file.readAsBytes())
              .timeout(const Duration(seconds: 5));
          codec.dispose();
          return file.path;
        } catch (_) {
          try {
            await file.delete();
          } catch (_) {}
          // fall through to a fresh download
        }
      }
    }

    final url = avatarPath.startsWith('http')
        ? avatarPath
        : '$baseUrl$avatarPath';
    final client = HttpClient();
    try {
      client.userAgent = AppConfig.userAgent;
      client.connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return null;
      final bytes =
          await consolidateHttpClientResponseBytes(response)
              .timeout(const Duration(seconds: 10));
      if (bytes.isEmpty || bytes.length > 512 * 1024) return null;
      // Validate the bytes actually decode - an invalid image handed to
      // plugin.show would break the whole notification.
      final codec = await ui.instantiateImageCodec(bytes)
          .timeout(const Duration(seconds: 5));
      codec.dispose();
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } finally {
      client.close();
    }
  } catch (_) {
    return null; // avatar is cosmetic: never break the notification
  }
}
