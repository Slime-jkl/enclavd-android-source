import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/utils/html_entities.dart';

void main() {
  group('decodeHtmlEntities', () {
    test('apostrophe entities decode to the quote character', () {
      expect(decodeHtmlEntities("I&#039;m here"), "I'm here");
      expect(decodeHtmlEntities('I&#39;m here'), "I'm here");
      expect(decodeHtmlEntities("I&apos;m here"), "I'm here");
    });

    test('htmlspecialchars ENT_QUOTES set decodes', () {
      expect(decodeHtmlEntities('a &amp; b'), 'a & b');
      expect(decodeHtmlEntities('&lt;script&gt;'), '<script>');
      expect(decodeHtmlEntities('say &quot;hi&quot;'), 'say "hi"');
      expect(decodeHtmlEntities('&quot;&#039;&amp;&lt;&gt;'), '"\'&<>');
    });

    test('plain text without ampersands is untouched', () {
      const text = 'just some words, no entities';
      expect(decodeHtmlEntities(text), text);
    });

    test('unknown named entities are left alone', () {
      expect(decodeHtmlEntities('&notanentity;'), '&notanentity;');
    });

    test('dangling ampersand without semicolon is kept', () {
      expect(decodeHtmlEntities('a & b'), 'a & b');
      expect(decodeHtmlEntities('ends with &'), 'ends with &');
    });

    test('decimal and hex numeric entities decode', () {
      expect(decodeHtmlEntities('&#65;&#66;'), 'AB');
      expect(decodeHtmlEntities('&#x41;&#X42;'), 'AB');
    });

    test('emoji / unicode numeric entities decode', () {
      expect(decodeHtmlEntities('&#128512;'), '\u{1F600}');
    });

    test('invalid code points are left as the original entity', () {
      // Lone surrogate: must not produce a broken string.
      expect(decodeHtmlEntities('&#55296;'), '&#55296;');
      // Out of range.
      expect(decodeHtmlEntities('&#1114112;'), '&#1114112;');
    });

    test('single pass only - no double decoding', () {
      // &amp;lt; must become &lt;, never <.
      expect(decodeHtmlEntities('&amp;lt;'), '&lt;');
      // &#039; encoded twice must stay &#039; once.
      expect(decodeHtmlEntities('&amp;#039;'), '&#039;');
    });

    test('realistic post body decodes exactly like the browser', () {
      const input = "I&#039;m loving #enclavd today &amp; it&#039;s great!";
      expect(decodeHtmlEntities(input), "I'm loving #enclavd today & it's great!");
    });
  });
}
