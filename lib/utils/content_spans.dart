import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../widgets/animated_emoji.dart';
import 'emoji.dart';

/// Post-body linkification, port of the site's render pipeline
/// (post_card.php: convertHashtagsToLinks + convertUrlsToLinks). Runs on
/// DECODED content, so a `#` is always a real hashtag - never the remnant
/// of an entity (the site needs its `(?<!&)` guard for that; the app
/// doesn't). Hashtags and URLs are link-blue with no underline (touch
/// screens never hover).
/// One tokenized piece of post content.
class ContentToken {
  const ContentToken(this.text, this.kind, {this.emojiName});

  final String text;

  /// 'hashtag' | 'url' | 'mention' | 'emoji' | 'plain'
  final String kind;

  /// Set when [kind] is 'emoji': the shortcode name without colons.
  final String? emojiName;

  bool get isHashtag => kind == 'hashtag';
  bool get isUrl => kind == 'url';
  bool get isMention => kind == 'mention';
  bool get isEmoji => kind == 'emoji';
  bool get isPlain => kind == 'plain';
}

/// `:name:` between word boundaries - the site's shortcode regex. Names are
/// validated against the bundled pack, so typos stay plain text.
final _shortcodeRe = RegExp(r'(?<!\w):([A-Za-z0-9][A-Za-z0-9_-]*):(?!\w)');

final _tokenRe = RegExp(
    r'(?:https?://|www\.)\S+|#[A-Za-z0-9_]+|(?<!\w):([A-Za-z0-9][A-Za-z0-9_-]*):(?!\w)');

/// Pure tokenizer: split [text] into hashtag / url / emoji / plain tokens.
/// A URL match wins over a hashtag inside it; trailing `.,:` punctuation is
/// stripped from URLs.
List<ContentToken> tokenizePostContent(String text) {
  final tokens = <ContentToken>[];
  var last = 0;
  for (final m in _tokenRe.allMatches(text)) {
    if (m.start > last) {
      tokens.add(ContentToken(text.substring(last, m.start), 'plain'));
    }
    final raw = m.group(0)!;
    if (raw.startsWith('http') || raw.startsWith('www')) {
      var url = raw;
      while (url.isNotEmpty && '.,:'.contains(url[url.length - 1])) {
        url = url.substring(0, url.length - 1);
      }
      if (url.isEmpty) {
        tokens.add(ContentToken(raw, 'plain'));
        last = m.end;
        continue;
      }
      tokens.add(ContentToken(url, 'url'));
      // Stripped punctuation stays outside the link (the site's
      // (?<![\.,:]) lookbehind does the same); advance only past the URL.
      last = m.start + url.length;
    } else if (raw.startsWith('#')) {
      tokens.add(ContentToken(raw, 'hashtag'));
      last = m.end;
    } else {
      final name = m.group(1)!.toLowerCase();
      tokens.add(emojiCatalog.contains(name)
          ? ContentToken(raw, 'emoji', emojiName: name)
          : ContentToken(raw, 'plain'));
      last = m.end;
    }
  }
  if (last < text.length) {
    tokens.add(ContentToken(text.substring(last), 'plain'));
  }
  return tokens;
}

/// Builds tappable inline spans for a post body. Link spans only override
/// the color; font size/height inherit from the enclosing Text style.
/// [recognizers] collects the created TapGestureRecognizers - the caller
/// owns them and MUST dispose them (creating recognizers in build()
/// without disposal leaks).
List<InlineSpan> postContentSpans(
  String text, {
  required Color linkColor,
  required void Function(String tag) onHashtag,
  required void Function(String url) onUrl,
  required List<TapGestureRecognizer> recognizers,
  double emojiSize = 18,
}) {
  final linkStyle = TextStyle(color: linkColor);
  final spans = <InlineSpan>[];
  for (final token in tokenizePostContent(text)) {
    if (token.isEmoji) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: AnimatedEmoji(name: token.emojiName!, size: emojiSize),
      ));
      continue;
    }
    if (token.isPlain) {
      spans.add(TextSpan(text: token.text));
      continue;
    }
    final recognizer = TapGestureRecognizer();
    recognizers.add(recognizer);
    if (token.isHashtag) {
      final tag = token.text.substring(1); // strip '#'
      recognizer.onTap = () => onHashtag(tag);
    } else {
      final url =
          token.text.startsWith('http') ? token.text : 'https://${token.text}';
      recognizer.onTap = () => onUrl(url);
    }
    spans.add(TextSpan(
      text: token.text,
      style: linkStyle,
      recognizer: recognizer,
    ));
  }
  return spans;
}

/// One tokenized piece of comment content: 'plain' | 'mention' | 'url'
/// (comments render NO hashtags, per the site's render_comment_content
/// pipeline: escape -> @mentions -> URLs).
class CommentToken {
  const CommentToken(this.text, this.kind, {this.emojiName});

  final String text;

  /// 'mention' | 'url' | 'emoji' | 'plain'
  final String kind;

  /// Set when [kind] is 'emoji': the shortcode name without colons.
  final String? emojiName;

  bool get isMention => kind == 'mention';
  bool get isUrl => kind == 'url';
  bool get isEmoji => kind == 'emoji';
  bool get isPlain => kind == 'plain';
}

/// Quote shown above a reply: whose reply it answers plus a collapsed
/// excerpt of that reply. The target comes from the reply relationship
/// (parent_comment_id, resolved server side). Rows written before that
/// carried the '@user wrote: "clamped"' prefix in their own text instead,
/// which parseCommentQuote still recognises.
class CommentQuote {
  const CommentQuote({
    required this.target,
    required this.text,
    required this.body,
  });

  final String target; // quoted author's username
  final String text; // the quoted text
  final String body; // the reply's own text after the prefix
}

/// Matches the app's quote prefix. Non-greedy: the quoted text is
/// whitespace-collapsed by the writer, so the first `"\n\n` ends it
/// (embedded double quotes survive because the terminator is `"\n\n`).
final _commentQuoteRe = RegExp(r'^@([A-Za-z0-9_]+) wrote: "(.*?)"\n\n');

/// Returns the quote prefix when the comment starts with one, else null.
CommentQuote? parseCommentQuote(String content) {
  final m = _commentQuoteRe.firstMatch(content);
  if (m == null) return null;
  return CommentQuote(
    target: m.group(1)!,
    text: m.group(2)!,
    body: content.substring(m.end),
  );
}

/// The site's convertMentionsToLinks regex, ported verbatim: the
/// lookbehind keeps `email@x` and `@@user` from linkifying mid-token.
final _commentTokenRe = RegExp(
    r'(?:https?://|www\.)\S+|(?<![\w@])@[A-Za-z0-9_]+|(?<!\w):([A-Za-z0-9][A-Za-z0-9_-]*):(?!\w)');

/// Comment tokenizer: @mentions + URLs + emoji shortcodes, no hashtags
/// (site parity). A URL match wins over a mention inside it; trailing
/// `.,:` is stripped.
List<CommentToken> tokenizeCommentContent(String text) {
  final tokens = <CommentToken>[];
  var last = 0;
  for (final m in _commentTokenRe.allMatches(text)) {
    if (m.start > last) {
      tokens.add(CommentToken(text.substring(last, m.start), 'plain'));
    }
    final raw = m.group(0)!;
    if (raw.startsWith('http') || raw.startsWith('www')) {
      var url = raw;
      while (url.isNotEmpty && '.,:'.contains(url[url.length - 1])) {
        url = url.substring(0, url.length - 1);
      }
      if (url.isEmpty) {
        tokens.add(CommentToken(raw, 'plain'));
        last = m.end;
        continue;
      }
      tokens.add(CommentToken(url, 'url'));
      // Stripped punctuation stays outside the link (the site's
      // (?<![\.,:]) lookbehind does the same); advance only past the URL.
      last = m.start + url.length;
    } else if (raw.startsWith('@')) {
      tokens.add(CommentToken(raw, 'mention'));
      last = m.end;
    } else {
      final name = m.group(1)!.toLowerCase();
      tokens.add(emojiCatalog.contains(name)
          ? CommentToken(raw, 'emoji', emojiName: name)
          : CommentToken(raw, 'plain'));
      last = m.end;
    }
  }
  if (last < text.length) {
    tokens.add(CommentToken(text.substring(last), 'plain'));
  }
  return tokens;
}

/// Tappable spans for comment content: @mentions (-> profile) + URLs (->
/// system browser), link-blue, no underline. Same recognizer-ownership
/// contract as postContentSpans.
List<InlineSpan> commentContentSpans(
  String text, {
  required Color linkColor,
  required void Function(String username) onMention,
  required void Function(String url) onUrl,
  required List<TapGestureRecognizer> recognizers,
  double emojiSize = 17,
}) {
  final linkStyle = TextStyle(color: linkColor);
  final spans = <InlineSpan>[];
  for (final token in tokenizeCommentContent(text)) {
    if (token.isEmoji) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: AnimatedEmoji(name: token.emojiName!, size: emojiSize),
      ));
      continue;
    }
    if (token.isPlain) {
      spans.add(TextSpan(text: token.text));
      continue;
    }
    final recognizer = TapGestureRecognizer();
    recognizers.add(recognizer);
    if (token.isMention) {
      final username = token.text.substring(1); // strip '@'
      recognizer.onTap = () => onMention(username);
    } else {
      final url =
          token.text.startsWith('http') ? token.text : 'https://${token.text}';
      recognizer.onTap = () => onUrl(url);
    }
    spans.add(TextSpan(
      text: token.text,
      style: linkStyle,
      recognizer: recognizer,
    ));
  }
  return spans;
}

/// Emoji-only spans for plain excerpts (quote cards, snackbars). Nothing is
/// linkified here: quoted text is context, not a second set of links.
List<InlineSpan> plainEmojiSpans(String text, {double emojiSize = 14}) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in _shortcodeRe.allMatches(text)) {
    final name = m.group(1)!.toLowerCase();
    if (!emojiCatalog.contains(name)) continue;
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
    }
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: AnimatedEmoji(name: name, size: emojiSize),
    ));
    last = m.end;
  }
  if (last < text.length) {
    spans.add(TextSpan(text: text.substring(last)));
  }
  return spans;
}
