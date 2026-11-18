import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:enclavd/api/feed_service.dart';
import 'package:enclavd/screens/compose_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/widgets/ui/app_button.dart';
import 'package:enclavd/widgets/ui/app_sheet.dart';

/// A real 1x1 PNG: the picked bytes have to decode for the bake to run.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

XFile _file(String name) => XFile.fromData(
      Uint8List.fromList(_pngBytes),
      name: name,
      mimeType: 'image/png',
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('compose sheet', () {
    testWidgets('opens as the standard bottom sheet', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => ComposeScreen.open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AppSheet), findsOneWidget);
      expect(find.text('Create post'), findsOneWidget,
          reason: 'the sheet supplies the title instead of an app bar');
    });

    testWidgets('edit mode names the sheet for editing', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => ComposeScreen.open(
                  context,
                  post: Post.fromJson(const {
                    'id': 1,
                    'content': 'hello',
                    'created_at': '2026-01-01 00:00:00',
                    'username': 'dev',
                    'rank': 'Member',
                  }),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Edit post'), findsOneWidget);
    });

    testWidgets('the add-image button greys out and stays still while baking',
        (tester) async {
      final bake = Completer<Uint8List>();
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: Scaffold(
          body: ComposeScreen(
            pickImages: () async => [_file('a.png'), _file('b.png')],
            bake: (_) => bake.future,
          ),
        ),
      ));

      await tester.tap(find.widgetWithText(AppButton, 'Add Image'));
      // The picks are in and held mid-preparation by the completer.
      await tester.pump();
      await tester.pump();

      final addMore = find.widgetWithText(AppButton, 'Add More');
      expect(addMore, findsOneWidget);
      final button = tester.widget<AppButton>(addMore);
      expect(button.onPressed, isNull,
          reason: 'the control must not accept a second pick while baking');
      expect(button.loading, isFalse,
          reason: 'the button itself must not spin - only the preview does');
      expect(button.icon, FontAwesomeIcons.image,
          reason: 'the icon stays put, nothing swaps for a spinner');
      expect(
        find.descendant(
          of: addMore,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );

      bake.complete(_pngBytes);
      await _settle(tester);

      final after = tester.widget<AppButton>(addMore);
      expect(after.onPressed, isNotNull,
          reason: 'the button comes back once every pick is prepared');
    });
  });
}
