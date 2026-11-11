import 'dart:io' show HttpDate;

/// HTTP freshness rules for the on-disk image cache.
///
/// Images are content-addressed by their URL, but the server still owns
/// freshness: `Cache-Control`, `Expires`, `ETag` and `Last-Modified` decide
/// when a cached copy may be served without asking the network. Keeping this
/// parser separate from the Flutter/provider plumbing makes the edge cases
/// (quoted directives, `no-store`, `no-cache`, `Vary: *`, invalid dates)
/// straightforward to test.
class ImageCachePolicy {
  const ImageCachePolicy({
    required this.maxAge,
    required this.cacheable,
    this.etag,
    this.lastModified,
    this.mustRevalidate = false,
  });

  /// How long the stored response stays fresh. Zero means "always revalidate".
  final Duration maxAge;

  /// False for `no-store` and `Vary: *` responses.
  final bool cacheable;

  final String? etag;
  final String? lastModified;

  /// `must-revalidate` is advisory for a private client cache, but keeping it
  /// lets the provider reject stale-on-error fallbacks when the server asked
  /// for strict revalidation.
  final bool mustRevalidate;

  bool isFresh(DateTime storedAt, DateTime now) {
    if (!cacheable || maxAge <= Duration.zero) return false;
    final age = now.difference(storedAt);
    return age >= Duration.zero && age < maxAge;
  }

  ImageCachePolicy copyWith({
    Duration? maxAge,
    bool? cacheable,
    String? etag,
    String? lastModified,
    bool? mustRevalidate,
  }) {
    return ImageCachePolicy(
      maxAge: maxAge ?? this.maxAge,
      cacheable: cacheable ?? this.cacheable,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      mustRevalidate: mustRevalidate ?? this.mustRevalidate,
    );
  }

  static ImageCachePolicy fromHeaders(
    Map<String, String> headers, {
    DateTime? receivedAt,
  }) {
    final now = receivedAt ?? DateTime.now();
    final cacheControl = _header(headers, 'cache-control');
    final directives = _parseDirectives(cacheControl);
    final noStore = directives.containsKey('no-store');
    final noCache = directives.containsKey('no-cache');
    final mustRevalidate = directives.containsKey('must-revalidate');

    final hasMaxAge = directives.containsKey('max-age');
    Duration? maxAge;
    if (hasMaxAge) {
      // A malformed or negative max-age is not a license to cache for the
      // default period; treat it as "revalidate immediately".
      maxAge = _parseSeconds(directives['max-age']) ?? Duration.zero;
    } else {
      final expiresHeader = _header(headers, 'expires');
      if (expiresHeader != null) {
        final expires = _parseHttpDate(expiresHeader);
        maxAge = expires == null
            ? Duration.zero
            : expires.difference(now);
      }
    }
    if (noCache) {
      maxAge = Duration.zero;
    } else {
      // No explicit freshness: a conservative default. The server sends a
      // one-year immutable max-age for media, so this is only a fallback for
      // proxies/misconfigured hosts.
      maxAge ??= const Duration(days: 1);
    }
    if (maxAge.isNegative) maxAge = Duration.zero;
    if (maxAge > const Duration(days: 365)) {
      maxAge = const Duration(days: 365);
    }

    final vary = _header(headers, 'vary');
    final varyStar = vary != null &&
        vary.split(',').any((value) => value.trim() == '*');
    return ImageCachePolicy(
      maxAge: maxAge,
      cacheable: !noStore && !varyStar,
      etag: _header(headers, 'etag'),
      lastModified: _header(headers, 'last-modified'),
      mustRevalidate: mustRevalidate,
    );
  }

  /// Case-insensitive lookup; `HttpHeaders.forEach` casing is not guaranteed
  /// across platforms.
  static String? _header(Map<String, String> headers, String name) {
    final wanted = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == wanted) return entry.value;
    }
    return null;
  }

  static Map<String, String> _parseDirectives(String? raw) {
    final result = <String, String>{};
    if (raw == null || raw.trim().isEmpty) return result;
    for (final part in raw.split(',')) {
      final piece = part.trim();
      if (piece.isEmpty) continue;
      final eq = piece.indexOf('=');
      if (eq < 0) {
        result[piece.toLowerCase()] = '';
        continue;
      }
      final name = piece.substring(0, eq).trim().toLowerCase();
      var value = piece.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      result[name] = value;
    }
    return result;
  }

  static Duration? _parseSeconds(String? raw) {
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
  }

  static DateTime? _parseHttpDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return HttpDate.parse(raw.trim());
    } catch (_) {
      return null;
    }
  }
}
