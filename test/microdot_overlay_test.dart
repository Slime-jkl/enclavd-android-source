import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/widgets/microdot_overlay.dart';

void main() {
  Finder watermark(String label) => find.byWidgetPredicate((w) =>
      w is CustomPaint && w.painter is MicrodotPainter &&
      (w.painter! as MicrodotPainter).label == label);

  testWidgets('logged-in id tiles the * user id * watermark', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MicrodotOverlay(resolveUserId: () async => 42),
    ));
    await tester.pump();

    expect(watermark('* 42 *'), findsOneWidget,
        reason: 'watermark carries the viewer user id, site format');
  });

  testWidgets('watermark never blocks touches (IgnorePointer)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MicrodotOverlay(resolveUserId: () async => 7),
    ));
    await tester.pump();

    expect(
        find.ancestor(
            of: watermark('* 7 *'),
            matching: find.byWidgetPredicate(
                (w) => w is IgnorePointer && w.ignoring)),
        findsOneWidget,
        reason: 'pointer-events: none like the site overlay');
  });

  testWidgets('logged out / no id renders nothing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MicrodotOverlay(resolveUserId: () async => null),
    ));
    await tester.pump();

    expect(find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is MicrodotPainter),
        findsNothing);
  });
}
