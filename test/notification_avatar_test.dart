import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/services/notification_avatar.dart';

/// A real 1x1 PNG — decode-valid, so instantiateImageCodec accepts it.
final tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  test('downloads, caches and reuses the avatar file', () async {
    var hits = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      hits++;
      req.response.headers.contentType = ContentType('image', 'png');
      req.response.add(tinyPng);
      await req.response.close();
    });
    final cache = await Directory.systemTemp.createTemp('avatar_test');
    addTearDown(() => cache.delete(recursive: true));

    final path1 = await resolveNotificationAvatar('/public/avatars/alice.png',
        baseUrl: 'http://127.0.0.1:${server.port}', cacheDir: cache);
    expect(path1, isNotNull);
    expect(File(path1!).existsSync(), isTrue);
    expect(hits, 1, reason: 'one download');

    final path2 = await resolveNotificationAvatar('/public/avatars/alice.png',
        baseUrl: 'http://127.0.0.1:${server.port}', cacheDir: cache);
    expect(path2, path1, reason: 'cache hit — no second download');
    expect(hits, 1);
  });

  test('invalid bytes are rejected and never cached', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      req.response.add('not an image'.codeUnits);
      await req.response.close();
    });
    final cache = await Directory.systemTemp.createTemp('avatar_test');
    addTearDown(() => cache.delete(recursive: true));

    final path = await resolveNotificationAvatar('/public/avatars/bad.png',
        baseUrl: 'http://127.0.0.1:${server.port}', cacheDir: cache);
    expect(path, isNull,
        reason: 'an undecodable image must never break plugin.show');
  });

  test('server failure returns null (the avatar is cosmetic)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    });
    final cache = await Directory.systemTemp.createTemp('avatar_test');
    addTearDown(() => cache.delete(recursive: true));

    expect(
        await resolveNotificationAvatar('/public/avatars/missing.png',
            baseUrl: 'http://127.0.0.1:${server.port}', cacheDir: cache),
        isNull);
  });

  test('absolute URLs are used as-is', () async {
    var hits = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      hits++;
      expect(req.uri.path, '/public/avatars/alice.png');
      req.response.headers.contentType = ContentType('image', 'png');
      req.response.add(tinyPng);
      await req.response.close();
    });
    final cache = await Directory.systemTemp.createTemp('avatar_test');
    addTearDown(() => cache.delete(recursive: true));

    final path = await resolveNotificationAvatar('http://127.0.0.1:${server.port}/public/avatars/alice.png',
        cacheDir: cache);
    expect(path, isNotNull);
    expect(hits, 1);
  });
}
