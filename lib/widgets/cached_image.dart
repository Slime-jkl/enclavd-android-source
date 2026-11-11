import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'image_cache_policy.dart';

/// Disk-backed ImageProvider for remote images.
///
/// The cache is deliberately boring and HTTP-correct:
/// - one atomic file per URL, plus a JSON index with `ETag`/`Last-Modified`
///   validators and the response freshness;
/// - fresh entries serve from disk without touching the network;
/// - stale entries revalidate with `If-None-Match`/`If-Modified-Since` and a
///   304 refreshes their freshness without re-downloading the bytes;
/// - `no-store`/`Vary: *` are honoured; failed revalidations may serve a
///   stale copy for offline UX;
/// - a bounded LRU (64 MiB / 400 entries) keeps the cache from growing
///   without limit;
/// - cache bookkeeping errors never break an image render.
///
/// This is intentionally only for remote images (feed posts, avatars,
/// covers); local assets still use Flutter's asset pipeline.
class CachedNetworkImageProvider
    extends ImageProvider<CachedNetworkImageProvider> {
  CachedNetworkImageProvider(this.url, {this.httpClientFactory});

  final String url;

  /// Injectable for tests; defaults to a plain HttpClient.
  final HttpClient Function()? httpClientFactory;

  static const String _cacheDirName = 'enclavd_img_v2';
  static const String _indexName = 'index.json';
  static const int _indexVersion = 2;
  static const int _maxBytes = 64 * 1024 * 1024;
  static const int _maxEntries = 400;
  static const int _maxImageBytes = 12 * 1024 * 1024;
  static const Duration _maxStaleOnError = Duration(days: 30);
  static const Duration _touchInterval = Duration(hours: 12);

  static Directory? _directory;
  static Map<String, _CacheEntry> _entries = <String, _CacheEntry>{};
  static Future<void>? _initFuture;
  static Future<void> _mutation = Future<void>.value();
  static final Map<String, Future<Uint8List>> _inflight =
      <String, Future<Uint8List>>{};
  static final Map<String, DateTime> _lastTouched = <String, DateTime>{};
  static HttpClient? _sharedClient;
  static bool _cacheDisabled = false;

  /// Cap the decoded-image memory cache. Feed images decode at display width,
  /// but a 1000-entry / 100 MiB default is too much headroom on low-end
  /// devices once avatars and covers are included.
  static void configureMemoryCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = 300;
    cache.maximumSizeBytes = 64 * 1024 * 1024;
  }

  @override
  Future<CachedNetworkImageProvider> obtainKey(
          ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _loadAsync(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await _cachedBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } catch (e) {
      // Surface the error to the caller's errorBuilder instead of hanging.
      throw Exception('Failed to load image: $url ($e)');
    }
  }

  /// Raw bytes for [url]: disk cache first, else a fresh/revalidated download.
  static Future<Uint8List> fetchBytes(
    String url, {
    HttpClient Function()? httpClientFactory,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw ArgumentError.value(url, 'url', 'Only http(s) URLs are cacheable');
    }
    if (!_cacheDisabled) {
      try {
        await _ensureInitialized();
      } catch (_) {
        // A broken/read-only cache directory must not take images down with
        // it: fall through to the network-only path for this session.
        _cacheDisabled = true;
      }
    }

    final entry = _entries[url];
    if (entry != null) {
      final file = _fileFor(entry);
      var exists = false;
      try {
        exists = await file.exists();
      } catch (_) {
        // Treat an unreadable cache entry as a miss.
      }
      if (exists && entry.policy.isFresh(entry.storedAt, DateTime.now())) {
        try {
          _markUsed(url, file);
          return await file.readAsBytes();
        } catch (_) {
          // A damaged file is a cache miss, not a render failure.
          await _removeEntry(url);
        }
      } else if (exists) {
        return await _download(
          url,
          uri,
          entry: entry,
          file: file,
          httpClientFactory: httpClientFactory,
        );
      } else {
        await _removeEntry(url);
      }
    }

    return _download(
      url,
      uri,
      httpClientFactory: httpClientFactory,
    );
  }

  Future<Uint8List> _cachedBytes() =>
      fetchBytes(url, httpClientFactory: httpClientFactory);

  /// Removes one URL from disk and from the decoded-image cache.
  ///
  /// The whole memory cache is cleared because the same bytes are normally
  /// wrapped in several `ResizeImage` keys and Flutter has no public API to
  /// evict every resize variant of one provider. This is rare (explicit
  /// invalidation), so correctness wins over the cheap path.
  static Future<void> invalidate(String url) async {
    if (_cacheDisabled) {
      _clearMemoryCache();
      return;
    }
    await _ensureInitialized();
    await _serialized(() async {
      final entry = _entries.remove(url);
      if (entry != null) await _deleteFile(entry);
      await _writeIndexLocked();
    });
    _clearMemoryCache();
  }

  /// Drops every cached image and the decoded-image cache. Call on logout or
  /// when the cache format changes.
  static Future<void> clear() async {
    if (_cacheDisabled) {
      _clearMemoryCache();
      return;
    }
    await _ensureInitialized();
    await _serialized(() async {
      final dir = _directory;
      if (dir != null && await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            try {
              await entity.delete();
            } catch (_) {
              // Best effort; reconcile on the next start.
            }
          }
        }
      }
      _entries.clear();
      await _writeIndexLocked();
    });
    _clearMemoryCache();
  }

  static Future<Uint8List> _download(
    String url,
    Uri uri, {
    _CacheEntry? entry,
    File? file,
    HttpClient Function()? httpClientFactory,
  }) {
    final existing = _inflight[url];
    if (existing != null) return existing;

    late final Future<Uint8List> future;
    future = _downloadOnce(
      url,
      uri,
      entry: entry,
      file: file,
      httpClientFactory: httpClientFactory,
    ).whenComplete(() {
      if (identical(_inflight[url], future)) _inflight.remove(url);
    });
    _inflight[url] = future;
    return future;
  }

  static Future<Uint8List> _downloadOnce(
    String url,
    Uri uri, {
    _CacheEntry? entry,
    File? file,
    HttpClient Function()? httpClientFactory,
  }) async {
    final injectedFactory = httpClientFactory;
    final client = injectedFactory?.call() ?? _sharedClientOrCreate();
    client.connectionTimeout ??= const Duration(seconds: 10);

    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8,*/*;q=0.5',
      );
      final etag = entry?.policy.etag;
      if (etag != null && etag.isNotEmpty) {
        request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      }
      final lastModified = entry?.policy.lastModified;
      if (lastModified != null && lastModified.isNotEmpty) {
        request.headers.set(
            HttpHeaders.ifModifiedSinceHeader, lastModified);
      }

      final response =
          await request.close().timeout(const Duration(seconds: 20));

      if (response.statusCode == HttpStatus.notModified &&
          entry != null &&
          file != null) {
        final bytes = await _readExisting(file);
        final headers = _headersToMap(response.headers);
        final fresh = ImageCachePolicy.fromHeaders(headers);
        final merged = _mergeNotModified(entry.policy, fresh, headers);
        if (!merged.cacheable) {
          await _removeEntry(url);
          return bytes;
        }
        await _updateMetadata(
          url,
          entry.copyWith(policy: merged, storedAt: DateTime.now()),
        );
        return bytes;
      }

      if (response.statusCode == 200) {
        final bytes = await _readBody(response);
        if (!_looksLikeImage(bytes)) {
          throw HttpException(
            'GET $url returned a non-image body',
            uri: uri,
          );
        }
        final headers = _headersToMap(response.headers);
        final policy = ImageCachePolicy.fromHeaders(headers);
        final mime = response.headers.contentType?.mimeType;
        if (!policy.cacheable) {
          await _removeEntry(url);
          return bytes;
        }
        await _store(url, bytes, policy, mime);
        return bytes;
      }

      // Drain the body so the connection can be pooled, then decide whether
      // a stale copy is better than an error.
      await response.drain<void>();
      final stale = await _staleBytes(entry, file);
      if (stale != null &&
          (response.statusCode >= 500 ||
              response.statusCode == HttpStatus.requestTimeout ||
              response.statusCode == HttpStatus.tooManyRequests)) {
        return stale;
      }
      if (response.statusCode == HttpStatus.notFound ||
          response.statusCode == HttpStatus.gone) {
        await _removeEntry(url);
      }
      throw HttpException('GET $url -> ${response.statusCode}', uri: uri);
    } on SocketException {
      final stale = await _staleBytes(entry, file);
      if (stale != null) return stale;
      rethrow;
    } on TimeoutException {
      final stale = await _staleBytes(entry, file);
      if (stale != null) return stale;
      rethrow;
    } finally {
      // Only a caller-injected client is ours to close; the shared client
      // keeps its TLS sessions and connections for the next image.
      if (injectedFactory != null) client.close(force: true);
    }
  }

  static Future<Uint8List> _readBody(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response) {
      total += chunk.length;
      if (total > _maxImageBytes) {
        throw const HttpException('Image exceeds the cache limit');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static Future<Uint8List> _readExisting(File file) async {
    try {
      return await file.readAsBytes();
    } catch (_) {
      throw const HttpException('Cached image vanished during revalidation');
    }
  }

  static Future<Uint8List?> _staleBytes(
    _CacheEntry? entry,
    File? file,
  ) async {
    if (entry == null || file == null) return null;
    if (entry.policy.mustRevalidate) return null;
    final age = DateTime.now().difference(entry.storedAt);
    if (age > _maxStaleOnError || age.isNegative) return null;
    try {
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static ImageCachePolicy _mergeNotModified(
    ImageCachePolicy old,
    ImageCachePolicy fresh,
    Map<String, String> headers,
  ) {
    final hasCacheControl = _hasHeader(headers, 'cache-control');
    final hasExpires = _hasHeader(headers, 'expires');
    return old.copyWith(
      maxAge: (hasCacheControl || hasExpires) ? fresh.maxAge : old.maxAge,
      cacheable: fresh.cacheable,
      etag: fresh.etag ?? old.etag,
      lastModified: fresh.lastModified ?? old.lastModified,
      mustRevalidate:
          hasCacheControl ? fresh.mustRevalidate : old.mustRevalidate,
    );
  }

  static bool _hasHeader(Map<String, String> headers, String name) {
    final wanted = name.toLowerCase();
    return headers.keys.any((key) => key.toLowerCase() == wanted);
  }

  static Map<String, String> _headersToMap(HttpHeaders headers) {
    final result = <String, String>{};
    headers.forEach((name, values) {
      result[name] = values.join(', ');
    });
    return result;
  }

  static Future<void> _store(
    String url,
    Uint8List bytes,
    ImageCachePolicy policy,
    String? mime,
  ) async {
    final dir = _directory;
    if (dir == null || _cacheDisabled) return;
    final now = DateTime.now();
    final name = _fileNameFor(url, mime);
    final file = File('${dir.path}/$name');
    final temp = File('${file.path}.tmp');

    try {
      await temp.writeAsBytes(bytes, flush: true);
      // rename(2) replaces on Android, but not on every host used for
      // development; remove the old file first so the cache behaves the same.
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (_) {
      // Disk full / read-only cache: render the bytes, skip persistence.
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      return;
    }

    final entry = _CacheEntry(
      file: name,
      storedAt: now,
      policy: policy,
      size: bytes.length,
      mime: mime,
    );

    try {
      await _serialized(() async {
        final old = _entries[url];
        if (old != null && old.file != name) await _deleteFile(old);
        _entries[url] = entry;
        await _pruneLocked();
        await _writeIndexLocked();
      });
    } catch (_) {
      // Index bookkeeping is best-effort; the file is reconciled next start.
    }
  }

  static Future<void> _updateMetadata(String url, _CacheEntry entry) async {
    try {
      await _serialized(() async {
        _entries[url] = entry;
        await _writeIndexLocked();
      });
    } catch (_) {
      // Keep serving the bytes even if the index cannot be written.
    }
  }

  static Future<void> _removeEntry(String url) async {
    try {
      await _serialized(() async {
        final entry = _entries.remove(url);
        if (entry != null) await _deleteFile(entry);
        await _writeIndexLocked();
      });
    } catch (_) {
      // Best effort.
    }
  }

  static void _markUsed(String url, File file) {
    final now = DateTime.now();
    final last = _lastTouched[url];
    if (last != null && now.difference(last) < _touchInterval) return;
    _lastTouched[url] = now;
    // LRU uses file mtime; touching on every hit would cause needless disk
    // metadata writes, so cap it to once per half day.
    unawaited(
      file.setLastModified(now).then<void>((_) {}, onError: (Object _) {}),
    );
  }

  static void _clearMemoryCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }

  static Future<void> _ensureInitialized() {
    final current = _initFuture;
    if (current != null) return current;

    late final Future<void> guarded;
    guarded = _initialize().onError((Object error, StackTrace stack) {
      if (identical(_initFuture, guarded)) _initFuture = null;
      Error.throwWithStackTrace(error, stack);
    });
    _initFuture = guarded;
    return guarded;
  }

  static Future<void> _initialize() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/$_cacheDirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    _directory = dir;

    // Remove the old format's directory once; it had no validators and its
    // 300-file cap did not bound bytes.
    final legacy = Directory('${base.path}/enclavd_img');
    if (await legacy.exists()) {
      try {
        await legacy.delete(recursive: true);
      } catch (_) {}
    }

    final indexFile = File('${dir.path}/$_indexName');
    final loaded = <String, _CacheEntry>{};
    var reset = false;
    if (await indexFile.exists()) {
      try {
        final decoded = jsonDecode(await indexFile.readAsString());
        if (decoded is! Map<String, dynamic> ||
            decoded['version'] != _indexVersion ||
            decoded['entries'] is! Map<String, dynamic>) {
          reset = true;
        } else {
          final rawEntries = decoded['entries'] as Map<String, dynamic>;
          rawEntries.forEach((url, value) {
            final entry = _entryFromJson(value);
            if (entry != null) loaded[url] = entry;
          });
        }
      } catch (_) {
        reset = true;
      }
    }
    if (reset) {
      await _deleteAllFiles(dir);
    }
    _entries = loaded;
    await _reconcileLocked();
    await _pruneLocked();
    await _writeIndexLocked();
  }

  static _CacheEntry? _entryFromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final file = raw['file'];
    final storedAt = raw['storedAt'];
    final maxAge = raw['maxAge'];
    final size = raw['size'];
    if (file is! String ||
        !_fileNamePattern.hasMatch(file) ||
        storedAt is! num ||
        maxAge is! num ||
        size is! num) {
      return null;
    }
    final stored = DateTime.fromMillisecondsSinceEpoch(
      storedAt.toInt(),
      isUtc: true,
    );
    final policy = ImageCachePolicy(
      maxAge: Duration(
        seconds: maxAge.toInt().clamp(0, 365 * 24 * 3600).toInt(),
      ),
      cacheable: true,
      etag: raw['etag'] is String ? raw['etag'] as String : null,
      lastModified:
          raw['lastModified'] is String ? raw['lastModified'] as String : null,
      mustRevalidate: raw['mustRevalidate'] == true,
    );
    return _CacheEntry(
      file: file,
      storedAt: stored,
      policy: policy,
      size: size.toInt().clamp(0, _maxImageBytes).toInt(),
      mime: raw['mime'] is String ? raw['mime'] as String : null,
    );
  }

  static Future<void> _reconcileLocked() async {
    final dir = _directory;
    if (dir == null) return;
    final present = <String>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name == _indexName || name.endsWith('.tmp')) {
        try {
          if (name.endsWith('.tmp')) await entity.delete();
        } catch (_) {}
        continue;
      }
      present.add(name);
    }

    _entries.removeWhere((url, entry) => !present.contains(entry.file));
    final referenced = _entries.values.map((entry) => entry.file).toSet();
    for (final name in present) {
      if (referenced.contains(name)) continue;
      try {
        await File('${dir.path}/$name').delete();
      } catch (_) {}
    }
  }

  static Future<void> _pruneLocked() async {
    if (_entries.isEmpty) return;
    var total = _entries.values.fold<int>(0, (sum, entry) => sum + entry.size);
    if (total <= _maxBytes && _entries.length <= _maxEntries) return;

    final rows = <_PruneRow>[];
    for (final item in _entries.entries.toList()) {
      final file = _fileFor(item.value);
      try {
        final stat = await file.stat();
        rows.add(_PruneRow(
          url: item.key,
          file: file,
          size: stat.size,
          modified: stat.modified,
        ));
      } catch (_) {
        _entries.remove(item.key);
        total -= item.value.size;
      }
    }
    rows.sort((a, b) => a.modified.compareTo(b.modified));

    final targetBytes = (_maxBytes * 0.85).floor();
    final targetCount = (_maxEntries * 0.85).floor();
    for (final row in rows) {
      if (total <= targetBytes && _entries.length <= targetCount) break;
      if (_entries.remove(row.url) == null) continue;
      total -= row.size;
      try {
        await row.file.delete();
      } catch (_) {}
    }
  }

  static Future<void> _writeIndexLocked() async {
    final dir = _directory;
    if (dir == null) return;
    final payload = <String, Object?>{
      'version': _indexVersion,
      'entries': <String, Object?>{
        for (final item in _entries.entries)
          item.key: <String, Object?>{
            'file': item.value.file,
            'storedAt': item.value.storedAt.millisecondsSinceEpoch,
            'maxAge': item.value.policy.maxAge.inSeconds,
            'etag': item.value.policy.etag,
            'lastModified': item.value.policy.lastModified,
            'mustRevalidate': item.value.policy.mustRevalidate,
            'size': item.value.size,
            'mime': item.value.mime,
          },
      },
    };
    final target = File('${dir.path}/$_indexName');
    final temp = File('${target.path}.tmp');
    final encoded = jsonEncode(payload);
    await temp.writeAsString(encoded, flush: true);
    try {
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
    } catch (_) {
      // Last resort: a torn index is detected and rebuilt on the next start.
      await target.writeAsString(encoded, flush: true);
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }

  static Future<void> _deleteAllFiles(Directory dir) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File) await entity.delete();
      }
    } catch (_) {}
  }

  static Future<void> _deleteFile(_CacheEntry entry) async {
    try {
      final file = _fileFor(entry);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static File _fileFor(_CacheEntry entry) =>
      File('${_directory!.path}/${entry.file}');

  static Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _mutation;
    final gate = Completer<void>();
    _mutation = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  static String _fileNameFor(String url, String? mime) {
    final hash = sha1Of(url);
    final ext = _extensionFor(url, mime);
    return '$hash.$ext';
  }

  static final RegExp _fileNamePattern =
      RegExp(r'^[0-9a-f]{16}\.[a-z0-9]{2,4}$');

  /// FNV-1a (63-bit) hex, stable across runs (unlike String.hashCode).
  ///
  /// Dart VM ints are signed 64-bit, so masking only 64 bits can yield a
  /// negative value and `toRadixString` would prefix a `-`, producing a
  /// filename the index parser rightly rejects (and every restart then
  /// treated those entries as orphans). Keeping the top bit clear avoids
  /// that class of bug.
  static String sha1Of(String input) {
    const mask = 0x7FFFFFFFFFFFFFFF;
    final bytes = utf8.encode(input);
    var hash = 0xcbf29ce484222325 & mask;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String _extensionFor(String url, String? mime) {
    switch (mime) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'image/avif':
        return 'avif';
    }
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot > path.length - 5) return 'bin';
    final ext = path.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{2,4}$').hasMatch(ext) ? ext : 'bin';
  }

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 12) return false;
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true; // JPEG
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true; // PNG
    }
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true; // GIF
    }
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true; // WebP
    }
    if (bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return true; // AVIF/HEIF container
    }
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true; // BMP
    return false;
  }

  static HttpClient _sharedClientOrCreate() {
    final existing = _sharedClient;
    if (existing != null) return existing;
    final client = HttpClient();
    client.userAgent = 'EnclavdApp/1.0';
    client.autoUncompress = true;
    client.maxConnectionsPerHost = 8;
    client.idleTimeout = const Duration(seconds: 30);
    _sharedClient = client;
    return client;
  }

  @override
  bool operator ==(Object other) =>
      other is CachedNetworkImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'CachedNetworkImageProvider($url)';
}

class _CacheEntry {
  const _CacheEntry({
    required this.file,
    required this.storedAt,
    required this.policy,
    required this.size,
    required this.mime,
  });

  final String file;
  final DateTime storedAt;
  final ImageCachePolicy policy;
  final int size;
  final String? mime;

  _CacheEntry copyWith({
    String? file,
    DateTime? storedAt,
    ImageCachePolicy? policy,
    int? size,
    String? mime,
  }) {
    return _CacheEntry(
      file: file ?? this.file,
      storedAt: storedAt ?? this.storedAt,
      policy: policy ?? this.policy,
      size: size ?? this.size,
      mime: mime ?? this.mime,
    );
  }
}

class _PruneRow {
  const _PruneRow({
    required this.url,
    required this.file,
    required this.size,
    required this.modified,
  });

  final String url;
  final File file;
  final int size;
  final DateTime modified;
}
