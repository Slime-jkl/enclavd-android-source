import 'package:flutter/painting.dart';
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
}
