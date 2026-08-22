import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:enclavd/widgets/enclavd_avatar.dart';

/// Geometry regression guard for the "oval avatar" report: the AppBar
/// leading forces its full 48×56 slot onto children with TIGHT constraints,
/// and BoxConstraints.enforce clamps a Container's width/height UP to the
/// parent's tight size — a bare Container avatar renders as a 48×56
/// ELLIPSE (ring AND image), the reported bug. The Align wrapper hands the
/// avatar loose constraints so its own size×size always wins.
///
/// Assertions (in the AppBar leading, the worst-case parent):
///  - the avatar's ring box is exactly size×size (32×32), never stretched;
///  - the clip and image boxes are exactly size−4 × size−4 (28×28 — the
///    border's 2px padding deflates the child), SQUARE, never an oval;
///  - the image uses cover fit.
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

    // The ring box (the Container inside the Align) — must be size×size.
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
        reason: 'the ring box must be exactly size×size — a tight parent '
            '(AppBar leading) must not stretch it into an ellipse');

    // The clip — square, and smaller than the ring by the border width.
    final clipFinder = find.descendant(
        of: find.byType(EnclavdAvatar), matching: find.byType(ClipOval));
    expect(clipFinder, findsOneWidget);
    expect(tester.getSize(clipFinder), const Size(inner, inner),
        reason: 'ClipOval must be square — a non-square clip IS the oval bug');

    // The SizedBox pinning the image — square.
    final boxFinder = find.descendant(
        of: find.byType(ClipOval), matching: find.byType(SizedBox));
    expect(boxFinder, findsOneWidget);
    expect(tester.getSize(boxFinder), const Size(inner, inner),
        reason: 'SizedBox must pin the image box to a square');
  });
}
