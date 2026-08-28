import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/theme/enclavd_theme.dart';
import 'package:enclavd/utils/content_spans.dart';

void main() {
  group('tokenizePostContent', () {
    test('plain text is one plain token', () {
      final tokens = tokenizePostContent('just some words');
      expect(tokens, hasLength(1));
      expect(tokens.single.kind, 'plain');
      expect(tokens.single.text, 'just some words');
    });

    test('hashtags tokenize', () {
      final tokens = tokenizePostContent('check #hashtag here');
      expect(tokens.map((t) => '${t.kind}:${t.text}'), [
        'plain:check ',
        'hashtag:#hashtag',
        'plain: here',
      ]);
    });

    test('hashtag allows underscores and digits', () {
      final tokens = tokenizePostContent('#tag_1');
      expect(tokens.single.kind, 'hashtag');
      expect(tokens.single.text, '#tag_1');
    });

    test('http and https urls tokenize', () {
      final tokens =
          tokenizePostContent('see https://enclavd.com now and http://x.io');
      expect(tokens.map((t) => '${t.kind}:${t.text}'), [
        'plain:see ',
        'url:https://enclavd.com',
        'plain: now and ',
        'url:http://x.io',
      ]);
    });

    test('www urls tokenize without a scheme', () {
      final tokens = tokenizePostContent('on www.example.com today');
      expect(tokens.any((t) => t.kind == 'url' && t.text == 'www.example.com'),
          isTrue);
    });

    test('trailing punctuation is stripped from urls', () {
      final tokens =
          tokenizePostContent('go to https://x.com. then https://y.com,');
      expect(tokens.map((t) => '${t.kind}:${t.text}'), [
        'plain:go to ',
        'url:https://x.com',
        'plain:. then ',
        'url:https://y.com',
        'plain:,',
      ]);
    });

    test('a hashtag inside a url stays part of the url', () {
      final tokens = tokenizePostContent('see https://x.com/#foo end');
      expect(tokens.map((t) => '${t.kind}:${t.text}'), [
        'plain:see ',
        'url:https://x.com/#foo',
        'plain: end',
      ]);
    });

    test('empty text yields no tokens', () {
      expect(tokenizePostContent(''), isEmpty);
    });

    test('decoded apostrophes do not create fake hashtags', () {
      // The site guards with (?<!&)# against &#039; entities; the app decodes
      // entities BEFORE tokenizing, so an apostrophe is never a hashtag.
      final tokens = tokenizePostContent("I'm #real");
      expect(tokens.map((t) => '${t.kind}:${t.text}'), [
        'plain:I\'m ',
        'hashtag:#real',
      ]);
    });
  });

  group('postContentSpans', () {
    test('plain text has no recognizers and no link style', () {
      final recs = <TapGestureRecognizer>[];
      final spans = postContentSpans(
        'hello world',
        onHashtag: (_) {},
        onUrl: (_) {},
        recognizers: recs,
      );
      expect(spans, hasLength(1));
      expect(recs, isEmpty);
      expect((spans.single as TextSpan).style, isNull);
    });

    test('hashtag span is link-colored and fires onHashtag with the bare tag',
        () {
      final recs = <TapGestureRecognizer>[];
      String? tapped;
      final spans = postContentSpans(
        '#viral',
        onHashtag: (tag) => tapped = tag,
        onUrl: (_) {},
        recognizers: recs,
      );
      final span = spans.single as TextSpan;
      expect(span.style?.color, EnclavdColors.link);
      expect(span.text, '#viral');
      expect(recs, hasLength(1));
      recs.single.onTap!();
      expect(tapped, 'viral');
    });

    test('url span fires onUrl with a scheme added for www links', () {
      final recs = <TapGestureRecognizer>[];
      String? opened;
      postContentSpans(
        'www.example.com',
        onHashtag: (_) {},
        onUrl: (url) => opened = url,
        recognizers: recs,
      );
      recs.single.onTap!();
      expect(opened, 'https://www.example.com');
    });

    test('http url passes through unchanged', () {
      final recs = <TapGestureRecognizer>[];
      String? opened;
      postContentSpans(
        'https://enclavd.com/x',
        onHashtag: (_) {},
        onUrl: (url) => opened = url,
        recognizers: recs,
      );
      recs.single.onTap!();
      expect(opened, 'https://enclavd.com/x');
    });
  });

  group('tokenizeCommentContent (render_comment_content port)', () {
    test('plain text is one plain token', () {
      final tokens = tokenizeCommentContent('just some words');
      expect(tokens, hasLength(1));
      expect(tokens.single.kind, 'plain');
    });

    test('a mention tokenizes with its @', () {
      final tokens = tokenizeCommentContent('hi @alice there');
      expect(tokens.map((t) => '${t.kind}:${t.text}'), [
        'plain:hi ',
        'mention:@alice',
        'plain: there',
      ]);
    });

    test('multiple mentions, each its own token', () {
      final tokens = tokenizeCommentContent('@a and @b_1');
      expect(tokens.map((t) => '${t.kind}:${t.text}'), [
        'mention:@a',
        'plain: and ',
        'mention:@b_1',
      ]);
    });

    test('mention inside a word is NOT a mention (site lookbehind)', () {
      // (?<![\w@]): email@x and @@user must stay plain.
      final tokens = tokenizeCommentContent('email@x.com and @@bob');
      expect(tokens.where((t) => t.isMention), isEmpty);
    });

    test('urls tokenize alongside mentions', () {
      final tokens =
          tokenizeCommentContent('see https://x.com @alice and www.y.io');
      expect(tokens.map((t) => '${t.kind}:${t.text}'), [
        'plain:see ',
        'url:https://x.com',
        'plain: ',
        'mention:@alice',
        'plain: and ',
        'url:www.y.io',
      ]);
    });

    test('a url wins over a mention inside it', () {
      final tokens = tokenizeCommentContent('https://x.com/@alice');
      expect(tokens.map((t) => '${t.kind}:${t.text}'),
          ['url:https://x.com/@alice']);
    });

    test('trailing punctuation stays outside url links', () {
      final tokens = tokenizeCommentContent('@a go to https://x.com. bye');
      expect(tokens.map((t) => '${t.kind}:${t.text}'), [
        'mention:@a',
        'plain: go to ',
        'url:https://x.com',
        'plain:. bye',
      ]);
    });

    test('no hashtags in comments (site parity)', () {
      final tokens = tokenizeCommentContent('#tag stays plain');
      expect(tokens.where((t) => t.kind == 'hashtag'), isEmpty);
      expect(tokens.single.kind, 'plain');
    });

    test('empty text yields no tokens', () {
      expect(tokenizeCommentContent(''), isEmpty);
    });
  });

  group('commentContentSpans', () {
    test('mention span is link-colored and fires onMention with bare name', () {
      final recs = <TapGestureRecognizer>[];
      String? tapped;
      final spans = commentContentSpans(
        'hello @alice',
        onMention: (username) => tapped = username,
        onUrl: (_) {},
        recognizers: recs,
      );
      final mentionSpan = spans.last as TextSpan;
      expect(mentionSpan.style?.color, EnclavdColors.link);
      expect(mentionSpan.text, '@alice');
      expect(recs, hasLength(1));
      recs.single.onTap!();
      expect(tapped, 'alice');
    });

    test('url span fires onUrl with a scheme added for www links', () {
      final recs = <TapGestureRecognizer>[];
      String? opened;
      commentContentSpans(
        'www.example.com',
        onMention: (_) {},
        onUrl: (url) => opened = url,
        recognizers: recs,
      );
      recs.single.onTap!();
      expect(opened, 'https://www.example.com');
    });
  });
}
