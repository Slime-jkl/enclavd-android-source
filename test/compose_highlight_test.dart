import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/screens/compose_screen.dart';
import 'package:enclavd/theme/enclavd_theme.dart';

void main() {
  group('highlightComposerSpans', () {
    test('plain text stays unstyled', () {
      final spans = highlightComposerSpans('just some words');
      expect(spans, hasLength(1));
      expect(spans.single.style, isNull);
    });

    test('hashtags get the link color', () {
      final spans = highlightComposerSpans('check #hashtag here');
      final tag = spans.firstWhere((s) => s is TextSpan && s.text == '#hashtag')
          as TextSpan;
      expect(tag.style?.color, EnclavdColors.link);
    });

    test('urls get the link color + underline', () {
      final spans = highlightComposerSpans('visit https://enclavd.com now');
      final url = spans.firstWhere(
          (s) => s is TextSpan && s.text == 'https://enclavd.com') as TextSpan;
      expect(url.style?.color, EnclavdColors.link);
      expect(url.style?.decoration, TextDecoration.underline);
    });

    test('www urls and mixed content tokenize', () {
      final spans =
          highlightComposerSpans('#tag1 www.example.com #tag2 http://x.io end');
      final texts = spans.whereType<TextSpan>().map((s) => s.text).toList();
      expect(texts, [
        '#tag1',
        ' ',
        'www.example.com',
        ' ',
        '#tag2',
        ' ',
        'http://x.io',
        ' end',
      ]);
    });

    test('empty text yields no spans', () {
      expect(highlightComposerSpans(''), isEmpty);
    });
  });

  group('composer field', () {
    testWidgets('typed text renders WHITE behind the transparent input',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: const ComposeScreen(),
      ));
      await tester.enterText(find.byType(TextField), 'hello world');
      await tester.pump();

      // The highlight layer is the only place the text is visible — the
      // input above it is transparent. It must carry the theme's white.
      final rich = tester.widget<Text>(find.byWidgetPredicate(
          (w) => w is Text && w.textSpan?.toPlainText() == 'hello world'));
      expect(rich.style?.color, EnclavdColors.textPrimary);
    });

    testWidgets('hashtags in the composer highlight in blue', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: const ComposeScreen(),
      ));
      await tester.enterText(find.byType(TextField), 'go #viral now');
      await tester.pump();

      final rich = tester.widget<Text>(find.byWidgetPredicate(
          (w) => w is Text && w.textSpan?.toPlainText() == 'go #viral now'));
      final spans = (rich.textSpan as TextSpan).children!;
      final tag = spans.firstWhere((s) => s is TextSpan && s.text == '#viral')
          as TextSpan;
      expect(tag.style?.color, EnclavdColors.link);
    });

    testWidgets(
        'input layer is zero-padded + top-aligned so the cursor lands on '
        'the visible text (the reported mismatch)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildEnclavdTheme(),
        home: const ComposeScreen(),
      ));
      final field = tester.widget<TextField>(find.byType(TextField));
      // The global inputDecorationTheme sets contentPadding (14,14) — the
      // transparent input MUST override it to zero or its cursor/text sit
      // 14px down-right of the highlight layer beneath (visible text).
      expect(field.decoration?.contentPadding, EdgeInsets.zero);
      // M3 can vertically center the EditableText when the box is taller
      // than the content — pin to top so it matches the highlight layer.
      expect(field.textAlignVertical, TextAlignVertical.top);
    });
  });
}
