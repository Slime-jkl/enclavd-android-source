import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

  test('a corrupt CACHED file is re-validated, deleted and re-downloaded '
      '(a partial write must never poison the 24h TTL)', () async {
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

    // 1) A valid download (hits == 1)...
    final path = await resolveNotificationAvatar('/public/avatars/alice.png',
        baseUrl: 'http://127.0.0.1:${server.port}', cacheDir: cache);
    expect(path, isNotNull);
    expect(hits, 1);

    // 2) ...then a process-kill-style partial write: non-empty garbage
    // that decodes fine by length but breaks the bitmap decode.
    final file = File(path!);
    await file.writeAsBytes('partial garbage'.codeUnits);
    expect(file.lengthSync(), greaterThan(0));

    // 3) The next resolve must NOT return the corrupt file — it re-validates,
    // deletes it and re-downloads (hits == 2).
    final path2 = await resolveNotificationAvatar('/public/avatars/alice.png',
        baseUrl: 'http://127.0.0.1:${server.port}', cacheDir: cache);
    expect(path2, isNotNull);
    expect(hits, 2,
        reason: 'the corrupt cache hit must trigger a fresh download');
    expect(File(path2!).readAsBytesSync(), tinyPng,
        reason: 'the returned file must be the valid re-download');
  });

  // THE 0.4.2 REGRESSION — messages stopped completely. The Person icon
  // was built with `FilePathAndroidBitmap(path) as AndroidIcon<Object>`:
  // FilePathAndroidBitmap implements AndroidBitmap<String> (a DIFFERENT
  // interface, for notificationDetails.bitmap), so the cast threw a
  // _TypeError on every show with a downloaded avatar. The correct class
  // for a Person icon is BitmapFilePathAndroidIcon (implements
  // AndroidIcon<String>, covariant to AndroidIcon<Object> — assignable,
  // no cast needed). Prove the bad cast throws and the good one works:
  test('Person icon must be an AndroidIcon, not an AndroidBitmap cast', () {
    final filePath = File(
            '${Directory.systemTemp.createTempSync('icon_cast_test').path}/a.png')
        .path;

    // The OLD code — a cast that ALWAYS throws at runtime. If anyone
    // reintroduces FilePathAndroidBitmap here, this test reds.
    expect(
      () => FilePathAndroidBitmap(filePath) as AndroidIcon<Object>,
      throwsA(isA<TypeError>()),
      reason: 'FilePathAndroidBitmap is an AndroidBitmap, not an AndroidIcon',
    );

    // The FIX — the plugin's file-path icon IS an AndroidIcon<String>,
    // and Dart covariance makes it assignable to Person.icon's
    // AndroidIcon<Object> without any cast.
    final icon = BitmapFilePathAndroidIcon(filePath);
    expect(icon, isA<AndroidIcon<String>>());
    expect(() => Person(key: 'them', name: 'sender', icon: icon),
        returnsNormally);
  });
}
