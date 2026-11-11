import 'dart:io' show HttpDate;

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/widgets/image_cache_policy.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);

  test('parses quoted max-age and validators', () {
    final policy = ImageCachePolicy.fromHeaders(
      {
        'Cache-Control': 'public, max-age="3600", immutable',
        'ETag': '"abc"',
        'Last-Modified': HttpDate.format(now),
      },
      receivedAt: now,
    );

    expect(policy.maxAge, const Duration(hours: 1));
    expect(policy.cacheable, isTrue);
    expect(policy.etag, '"abc"');
    expect(policy.lastModified, isNotNull);
    expect(policy.isFresh(now.subtract(const Duration(minutes: 59)), now),
        isTrue);
    expect(policy.isFresh(now.subtract(const Duration(hours: 1)), now), isFalse);
  });

  test('no-store is never cacheable', () {
    final policy = ImageCachePolicy.fromHeaders(
      {'cache-control': 'no-store, max-age=3600'},
      receivedAt: now,
    );

    expect(policy.cacheable, isFalse);
    expect(policy.isFresh(now, now), isFalse);
  });

  test('no-cache is stored but always revalidated', () {
    final policy = ImageCachePolicy.fromHeaders(
      {'cache-control': 'no-cache, max-age=999'},
      receivedAt: now,
    );

    expect(policy.cacheable, isTrue);
    expect(policy.maxAge, Duration.zero);
    expect(policy.isFresh(now, now), isFalse);
  });

  test('Vary star disables caching even with a max-age', () {
    final policy = ImageCachePolicy.fromHeaders(
      {
        'Cache-Control': 'max-age=3600',
        'Vary': 'Accept-Encoding, *',
      },
      receivedAt: now,
    );

    expect(policy.cacheable, isFalse);
  });

  test('Expires is a fallback when Cache-Control is absent', () {
    final policy = ImageCachePolicy.fromHeaders(
      {'Expires': HttpDate.format(now.add(const Duration(hours: 2)))},
      receivedAt: now,
    );

    expect(policy.maxAge, const Duration(hours: 2));
  });

  test('missing freshness headers use a conservative default', () {
    final policy = ImageCachePolicy.fromHeaders({}, receivedAt: now);

    expect(policy.maxAge, const Duration(days: 1));
    expect(policy.cacheable, isTrue);
    expect(policy.etag, isNull);
  });

  test('invalid and negative max-age force revalidation', () {
    final invalid = ImageCachePolicy.fromHeaders(
      {'cache-control': 'max-age=soon'},
      receivedAt: now,
    );
    final negative = ImageCachePolicy.fromHeaders(
      {'cache-control': 'max-age=-10'},
      receivedAt: now,
    );

    expect(invalid.maxAge, Duration.zero);
    expect(negative.maxAge, Duration.zero);
  });

  test('absurd max-age is capped at one year', () {
    final policy = ImageCachePolicy.fromHeaders(
      {'cache-control': 'max-age=999999999'},
      receivedAt: now,
    );

    expect(policy.maxAge, const Duration(days: 365));
  });

  test('must-revalidate is retained for stale-on-error decisions', () {
    final policy = ImageCachePolicy.fromHeaders(
      {'cache-control': 'must-revalidate, max-age=0'},
      receivedAt: now,
    );

    expect(policy.mustRevalidate, isTrue);
    expect(policy.isFresh(now, now), isFalse);
  });

  test('expired Expires yields a zero freshness window', () {
    final policy = ImageCachePolicy.fromHeaders(
      {'Expires': HttpDate.format(now.subtract(const Duration(hours: 1)))},
      receivedAt: now,
    );

    expect(policy.maxAge, Duration.zero);
    expect(policy.isFresh(now, now), isFalse);
  });

  test('malformed Expires is treated as already expired', () {
    for (final value in ['0', '-1', 'not-a-date']) {
      final policy = ImageCachePolicy.fromHeaders(
        {'Expires': value},
        receivedAt: now,
      );

      expect(policy.maxAge, Duration.zero, reason: value);
    }
  });
}
