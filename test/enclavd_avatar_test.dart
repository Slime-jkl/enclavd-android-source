import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enclavd/widgets/enclavd_avatar.dart';

/// Geometry regression guard for the oval avatar report: the AppBar leading
/// forces tight constraints, so the avatar is wrapped in Align to keep its
/// size x size box.
void main() {
  testWidgets('avatar stays square even inside the tight AppBar leading',
      (tester) async {
    const size = 32.0;
    const inner = size - 4.0; // 2px border padding each side

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          leading: const Padding(
            padding: EdgeInsets.only(left: 8),
            child: InkWell(
              onTap: null,
              borderRadius: BorderRadius.all(Radius.circular(20)),
              child: EnclavdAvatar(
                size: 32,
                url: 'https://enclavd.com/public/avatars/probe.jpg',
                borderColor: Color(0xFFA855F7),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    // The ring box (Container inside the Align) must be size x size.
    final ringFinder = find.descendant(
        of: find.byType(EnclavdAvatar),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            (w.constraints?.isTight ?? false) &&
            (w.decoration is BoxDecoration) &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle &&
            (w.decoration! as BoxDecoration).border != null));
    expect(ringFinder, findsOneWidget);
    expect(tester.getSize(ringFinder), const Size(size, size),
        reason: 'the ring box must be exactly sizexsize - a tight parent '
            '(AppBar leading) must not stretch it into an ellipse');

    // The clip: square, smaller than the ring by the border width.
    final clipFinder = find.descendant(
        of: find.byType(EnclavdAvatar), matching: find.byType(ClipOval));
    expect(clipFinder, findsOneWidget);
    expect(tester.getSize(clipFinder), const Size(inner, inner),
        reason: 'ClipOval must be square - a non-square clip IS the oval bug');

    // The SizedBox pinning the image: square.
    final boxFinder = find.descendant(
        of: find.byType(ClipOval), matching: find.byType(SizedBox));
    expect(boxFinder, findsOneWidget);
    expect(tester.getSize(boxFinder), const Size(inner, inner),
        reason: 'SizedBox must pin the image box to a square');
  });
}
