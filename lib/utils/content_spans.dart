import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';

import '../theme/enclavd_theme.dart';

/// Post-body linkification — port of the site's render pipeline
/// (post_card.php: convertHashtagsToLinks + convertUrlsToLinks).
///
/// Runs on DECODED content (Post.fromJson already decoded HTML entities), so
/// a `#` is always a real hashtag — never the remnant of an `&#039;` entity
/// (the site needs its `(?<!&)` guard for that; the app doesn't).
///
/// Tokens, exactly like the site:
///   - hashtags: `#[A-Za-z0-9_]+`        → blue, tap → hashtag page
///   - URLs:     `https?://…` / `www.…`  → blue, tap → open in browser
///     (trailing `.,:` punctuation excluded, like the site's `(?<![\.,:])`)
///
/// Styling matches the site's `text-blue-400 hover:text-blue-300` classes —
/// link-blue, no underline (the site only underlines on hover, which a touch
/// screen never shows).

/// One tokenized piece of post content.
class ContentToken {
  const ContentToken(this.text, this.kind);

  final String text;

  /// 'hashtag' | 'url' | 'mention' | 'plain'
  final String kind;

  bool get isHashtag => kind == 'hashtag';
  bool get isUrl => kind == 'url';
  bool get isMention => kind == 'mention';
  bool get isPlain => kind == 'plain';
}

final _tokenRe = RegExp(r'(?:https?://|www\.)\S+|#[A-Za-z0-9_]+');

/// Pure tokenizer: split [text] into hashtag / url / plain tokens.
///
/// A URL match wins over a hashtag inside it (`https://x.com/#foo` is one
/// URL token — the same way the site's URL regex swallows it). Trailing
/// `.,:` punctuation is stripped from URLs.
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
      // The stripped punctuation stays OUTSIDE the link (the site's
      // (?<![\.,:]) lookbehind does the same) — advance only past the URL
      // proper so it falls into the next plain segment.
      last = m.start + url.length;
    } else {
      tokens.add(ContentToken(raw, 'hashtag'));
      last = m.end;
    }
  }
  if (last < text.length) {
    tokens.add(ContentToken(text.substring(last), 'plain'));
  }
  return tokens;
}

/// Build tappable inline spans for a post body.
///
/// Link spans only override the color; font size/height inherit from the
/// enclosing Text widget's style (the same way the site's classes leave the
/// inherited font alone). [recognizers] collects the created
/// TapGestureRecognizers — the caller owns them and MUST dispose them (a
/// State's dispose() is the right place; creating recognizers in build()
/// without disposal leaks).
List<InlineSpan> postContentSpans(
  String text, {
  required void Function(String tag) onHashtag,
  required void Function(String url) onUrl,
  required List<TapGestureRecognizer> recognizers,
}) {
  const linkStyle = TextStyle(color: EnclavdColors.link);
  final spans = <InlineSpan>[];
  for (final token in tokenizePostContent(text)) {
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
      final url = token.text.startsWith('http') ? token.text : 'https://${token.text}';
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

/// One tokenized piece of comment content.
///
/// Comments render differently from posts (the site's render_comment_content
/// pipeline: escape → @mentions → URLs, NO hashtags). Tokens are
/// 'plain' | 'mention' | 'url'.
class CommentToken {
  const CommentToken(this.text, this.kind);

  final String text;

  /// 'mention' | 'url' | 'plain'
  final String kind;

  bool get isMention => kind == 'mention';
  bool get isUrl => kind == 'url';
  bool get isPlain => kind == 'plain';
}

/// Mention pattern — the site's convertMentionsToLinks regex, ported
/// verbatim: `(?<![\w@])@([a-zA-Z0-9_]+)`. The lookbehind keeps `email@x`
/// and `@@user` from linkifying mid-token.
final _commentTokenRe = RegExp(
    r'(?:https?://|www\.)\S+|(?<![\w@])@[A-Za-z0-9_]+');

/// Comment tokenizer: @mentions + URLs (the site's comment pipeline; no
/// hashtags). A URL match wins over a mention inside it (`https://x.com/@u`
/// is one URL token — same precedence as the post tokenizer). Trailing
/// `.,:` punctuation is stripped from URLs like the site's `(?<![.,:])`.
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
      // The stripped punctuation stays OUTSIDE the link (the site's
      // (?<![.,:]) lookbehind does the same) — advance only past the URL
      // proper so it falls into the next plain segment.
      last = m.start + url.length;
    } else {
      tokens.add(CommentToken(raw, 'mention'));
      last = m.end;
    }
  }
  if (last < text.length) {
    tokens.add(CommentToken(text.substring(last), 'plain'));
  }
  return tokens;
}

/// Build tappable inline spans for comment content — the app-side port of
/// the site's render_comment_content: @mentions (→ profile) + URLs (→
/// system browser), link-blue, no underline. No hashtags (site parity).
///
/// [recognizers] collects the created TapGestureRecognizers — the caller
/// owns them and MUST dispose them (same contract as postContentSpans).
List<InlineSpan> commentContentSpans(
  String text, {
  required void Function(String username) onMention,
  required void Function(String url) onUrl,
  required List<TapGestureRecognizer> recognizers,
}) {
  const linkStyle = TextStyle(color: EnclavdColors.link);
  final spans = <InlineSpan>[];
  for (final token in tokenizeCommentContent(text)) {
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
      final url = token.text.startsWith('http') ? token.text : 'https://${token.text}';
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
