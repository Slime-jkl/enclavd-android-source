import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/services/gallery_saver.dart';

void main() {
  group('GallerySaver.saveImage', () {
    final bytes = Uint8List.fromList([1, 2, 3]);

    test('success saves into the Enclavd album and confirms', () async {
      String? savedAlbum;
      final saver = GallerySaver(
        fetchBytes: (_) async => bytes,
        saveBytes: (b, {album}) async {
          expect(b, bytes);
          savedAlbum = album;
        },
      );

      final msg = await saver.saveImage('https://example.com/x.jpg');

      expect(msg, 'Saved to the Enclavd folder in your gallery');
      expect(savedAlbum, 'Enclavd');
    });

    test('download failure says the image could not be downloaded', () async {
      final saver = GallerySaver(
        fetchBytes: (_) async => throw const HttpException('GET 400'),
        saveBytes: (b, {album}) async => fail('must not reach the gallery'),
      );

      expect(await saver.saveImage('https://example.com/x.jpg'),
          "Couldn't download the image.");
    });

    test('permission denial on legacy devices points to Settings', () async {
      final saver = GallerySaver(
        fetchBytes: (_) async => bytes,
        saveBytes: (b, {album}) async =>
            throw PlatformException(code: 'permission_denied'),
      );

      expect(await saver.saveImage('https://example.com/x.jpg'),
          'Storage permission needed — allow it in Settings, then try again');
    });

    test('any other platform error gives a generic message', () async {
      final saver = GallerySaver(
        fetchBytes: (_) async => bytes,
        saveBytes: (b, {album}) async =>
            throw PlatformException(code: 'unknown_error'),
      );

      expect(await saver.saveImage('https://example.com/x.jpg'),
          "Couldn't save the image.");
    });

    test('unexpected errors never escape — generic message returned',
        () async {
      final saver = GallerySaver(
        fetchBytes: (_) async => throw StateError('boom'),
        saveBytes: (b, {album}) async => fail('must not reach the gallery'),
      );

      expect(await saver.saveImage('https://example.com/x.jpg'),
          "Couldn't save the image.");
    });
  });
}
