// One-off live check: the app's real ApiClient + SiteConfigService against the
// dev stack, proving the seasonal wordmark reaches BrandingService and that the
// resolved URL the app would request actually serves the art.
// Runs against whatever window the dev site_config currently has open.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:enclavd/api/api_client.dart';
import 'package:enclavd/api/site_config_service.dart';
import 'package:enclavd/services/branding_service.dart';

class MemStore implements SessionStore {
  List<SessionCookie> cookies = const [];
  @override
  Future<List<SessionCookie>> load() async => cookies;
  @override
  Future<void> save(List<SessionCookie> c) async => cookies = List.of(c);
  @override
  Future<void> clear() async => cookies = [];
}

Future<void> main() async {
  const base = 'https://localhost';
  final api = ApiClient(
    store: MemStore(),
    apiBaseUrl: base,
    httpClientFactory: () {
      final c = HttpClient();
      c.userAgent = 'EnclavdNative/2.1.2';
      c.connectionTimeout = const Duration(seconds: 15);
      c.badCertificateCallback = (cert, host, port) => true; // dev self-signed
      return c;
    },
  );

  var failures = 0;
  void check(String label, bool ok, [String? detail]) {
    print('${ok ? 'PASS' : 'FAIL'}  $label${detail != null ? ' - $detail' : ''}');
    if (!ok) failures++;
  }

  final cfg = await SiteConfigService(api).fetch();
  print('config.branding -> seasonal: ${cfg.seasonalLogo}  light: ${cfg.seasonalLogoLight}');
  check('config carries the seasonal wordmark',
      cfg.seasonalLogo == '/assets/enclavd-xmas-logo.png');
  check('light variant empty until the site ships one', cfg.seasonalLogoLight == null);
  check('BrandingService picked it up',
      BrandingService.instance.wordmark.value == '/assets/enclavd-xmas-logo.png');

  // Resolve exactly like BrandLogo does in a release build, then request the
  // same path from the dev stack (prod has the art only after deploy).
  final resolved = BrandingService.resolveUrl(
      BrandingService.instance.wordmark.value)!;
  print('release build would request: $resolved');
  check('resolves against the production host',
      resolved == 'https://enclavd.com/assets/enclavd-xmas-logo.png');
  final devUrl = resolved.replaceFirst('https://enclavd.com', base);
  final client = HttpClient()
    ..userAgent = 'EnclavdNative/2.1.2'
    ..badCertificateCallback = (cert, host, port) => true;
  final req = await client.getUrl(Uri.parse(devUrl));
  final res = await req.close();
  final bytes = await res.fold<int>(0, (n, chunk) => n + chunk.length);
  check('the art answers 200', res.statusCode == 200, '${res.statusCode}');
  check('served as an image', '${res.headers.contentType}'.contains('image/png'),
      '${res.headers.contentType}');
  check('non-trivial payload', bytes > 1000, '$bytes bytes');
  client.close(force: true);

  print(failures == 0 ? '\nALL BRANDING PATHS OK' : '\n$failures FAILED');
  if (failures > 0) throw StateError('$failures branding checks failed');
}
