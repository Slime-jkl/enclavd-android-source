import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enclavd/services/branding_service.dart';
import 'package:enclavd/widgets/brand_logo.dart';
import 'package:enclavd/widgets/enclavd_image.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    );

String? _bundledAsset(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  final provider = image.image;
  return provider is AssetImage ? provider.assetName : null;
}

void main() {
  tearDown(() => BrandingService.instance.update());

  test('site-relative paths resolve against the host this build talks to', () {
    expect(BrandingService.resolveUrl('/assets/enclavd-xmas-logo.png'),
        'https://enclavd.com/assets/enclavd-xmas-logo.png');
    expect(BrandingService.resolveUrl('https://cdn.example/x.png'),
        'https://cdn.example/x.png');
    expect(BrandingService.resolveUrl(''), isNull);
    expect(BrandingService.resolveUrl(null), isNull);
  });

  testWidgets('bundled wordmark when the site serves no seasonal art',
      (tester) async {
    await tester.pumpWidget(_host(const BrandLogo(height: 22)));

    expect(find.byType(EnclavdImage), findsNothing);
    expect(_bundledAsset(tester), 'assets/images/enclavd-logo-white.png');
  });

  testWidgets('swaps in the seasonal art when config lands after first paint',
      (tester) async {
    await tester.pumpWidget(_host(const BrandLogo(height: 22)));
    expect(find.byType(EnclavdImage), findsNothing);

    BrandingService.instance.update(dark: '/assets/enclavd-xmas-logo.png');
    await tester.pump();

    final image = tester.widget<EnclavdImage>(find.byType(EnclavdImage));
    expect(image.url, 'https://enclavd.com/assets/enclavd-xmas-logo.png');
    // Twice the wordmark height: the art carries decoration above and below
    // the letters, so the same height would read smaller.
    expect(image.height, 44);
  });

  testWidgets('light theme keeps the bundled dark-ink mark without a variant',
      (tester) async {
    BrandingService.instance.update(dark: '/assets/enclavd-xmas-logo.png');
    await tester.pumpWidget(
        _host(const BrandLogo(height: 22), brightness: Brightness.light));

    expect(find.byType(EnclavdImage), findsNothing);
    expect(_bundledAsset(tester), 'assets/images/enclavd-logo-dark.png');
  });

  testWidgets('light theme takes the variant when the site ships one',
      (tester) async {
    BrandingService.instance
        .update(dark: '/assets/xmas.png', light: '/assets/xmas-dark.png');
    await tester.pumpWidget(
        _host(const BrandLogo(height: 22), brightness: Brightness.light));

    final image = tester.widget<EnclavdImage>(find.byType(EnclavdImage));
    expect(image.url, 'https://enclavd.com/assets/xmas-dark.png');
  });
}
