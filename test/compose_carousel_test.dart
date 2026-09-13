import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:enclavd/screens/compose_screen.dart';
import 'package:enclavd/screens/image_editor_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

/// A real 1x1 PNG: the picked bytes have to decode for the bake to run.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

XFile _file(String name) => XFile.fromData(
      Uint8List.fromList(_pngBytes),
      name: name,
      mimeType: 'image/png',
    );

Finder findFa(FaIconData icon) => find.byWidgetPredicate((w) =>
    w is FaIcon && w.icon != null && w.icon!.codePoint == icon.codePoint);

/// Bounded pumps only: the composer shows a spinner while it bakes, so
/// pumpAndSettle would never settle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pump(
  WidgetTester tester,
  Future<List<XFile>> Function() picker,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildEnclavdTheme(),
    home: ComposeScreen(pickImages: picker),
  ));
  await tester.pump();
}

Future<void> _pick(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await _settle(tester);
}

void main() {
  group('composer carousel', () {
    testWidgets('several picked images land in the strip in order',
        (tester) async {
      await _pump(tester, () async => [_file('a.png'), _file('b.png'), _file('c.png')]);

      await _pick(tester, 'Add Image');

      expect(findFa(FontAwesomeIcons.xmark), findsNWidgets(3),
          reason: 'one remove badge per slide');
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('3/6 images - tap to edit'), findsOneWidget);
      expect(find.text('Add More'), findsOneWidget);
    });

    testWidgets('removing a slide drops it from the strip', (tester) async {
      await _pump(tester, () async => [_file('a.png'), _file('b.png'), _file('c.png')]);
      await _pick(tester, 'Add Image');

      await tester.tap(findFa(FontAwesomeIcons.xmark).first);
      await tester.pump();

      expect(findFa(FontAwesomeIcons.xmark), findsNWidgets(2));
      expect(find.text('2/6 images - tap to edit'), findsOneWidget);
    });

    testWidgets('a pick beyond the cap is refused with a message',
        (tester) async {
      await _pump(
          tester, () async => [for (var i = 0; i < 7; i++) _file('$i.png')]);

      await _pick(tester, 'Add Image');

      expect(find.text('Up to 6 images per post.'), findsOneWidget);
      expect(findFa(FontAwesomeIcons.xmark), findsNothing);
      expect(find.text('Add Image'), findsOneWidget,
          reason: 'nothing was attached, so the picker is still the offer');
    });

    testWidgets('adding a second batch keeps the first slides', (tester) async {
      var call = 0;
      await _pump(tester, () async {
        call++;
        return call == 1
            ? [_file('a.png'), _file('b.png')]
            : [_file('c.png')];
      });

      await _pick(tester, 'Add Image');
      expect(find.text('2/6 images - tap to edit'), findsOneWidget);

      await _pick(tester, 'Add More');
      expect(find.text('3/6 images - tap to edit'), findsOneWidget);
      expect(findFa(FontAwesomeIcons.xmark), findsNWidgets(3));
    });

    testWidgets('a single pick still opens the editor straight away',
        (tester) async {
      await _pump(tester, () async => [_file('only.png')]);

      await _pick(tester, 'Add Image');

      expect(find.byType(ImageEditorScreen), findsOneWidget);
      expect(find.text('3/6 images - tap to edit'), findsNothing,
          reason: 'one image keeps the plain preview');
    });
  });
}
