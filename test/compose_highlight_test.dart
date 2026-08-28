import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/screens/compose_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

void main() {
  group('composer field (Instagram/Facebook-style plain input)', () {
    testWidgets('is a single plain TextField with visible white text',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: const ComposeScreen(),
      ));

      // Exactly ONE TextField: no transparent input + highlight layer stack anymore.
      expect(find.byType(TextField), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      // The text is visible directly (no color: transparent trick).
      expect(field.style?.color, EnclavdColors.textPrimary);
      expect(field.controller?.text, 'hello world');
    });

    testWidgets('no focus outline - the theme blue border is suppressed',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: const ComposeScreen(),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      final d = field.decoration!;
      expect(d.filled, isFalse);
      expect(d.border, InputBorder.none);
      expect(d.enabledBorder, InputBorder.none);
      expect(d.focusedBorder, InputBorder.none,
          reason: 'the theme focusedBorder (blue OutlineInputBorder) must '
              'not appear on focus');
      // The container's own padding positions the text, not extra content padding.
      expect(d.contentPadding, EdgeInsets.zero);
    });

    testWidgets('carries the site\'s Quill placeholder', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: const ComposeScreen(),
      ));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.hintText, 'Write post..');
    });

    testWidgets('character counter still updates', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: const ComposeScreen(),
      ));
      await tester.enterText(find.byType(TextField), '12345');
      await tester.pump();
      expect(find.text('5/2000 characters'), findsOneWidget);
    });
  });
}
