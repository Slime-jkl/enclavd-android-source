import '../api/articles_service.dart';

/// Builds the article body document rendered in the detail screen's WebView.
///
/// The site (article.php) decodes the stored content with
/// htmlspecialchars_decode() and echoes it raw inside `.article-content` —
/// this is the same document, self-contained: the content HTML is injected
/// as-is and the CSS is a mobile-adapted port of the site's
/// `.article-content` rules (headings, lists, blockquote, pre/code, images,
/// Quill alignment classes) on the app's card background.
///
/// The "Continue Reading" section (the site's related-articles grid) is
/// appended as tappable cards; their /article/<slug> links are intercepted
/// by the WebView's navigation delegate and pushed as native detail screens.
///
/// Relative media URLs resolve against [baseUrl] (loadHtmlString baseUrl).
String buildArticleHtml({
  required String contentHtml,
  required List<ArticleSummary> related,
  required String baseUrl,
}) {
  const css = '''
    @font-face {
      font-family: 'Montserrat';
      src: url('assets/fonts/Montserrat/Montserrat-VariableFont_wght.ttf') format('truetype');
      font-weight: 100 900;
      font-style: normal;
      font-display: swap;
    }
    @font-face {
      font-family: 'Montserrat';
      src: url('assets/fonts/Montserrat/Montserrat-Italic-VariableFont_wght.ttf') format('truetype');
      font-weight: 100 900;
      font-style: italic;
      font-display: swap;
    }
    body {
      margin: 0;
      padding: 14px 16px 24px;
      background: #030712;
      color: #d1d5db;
      font-family: 'Montserrat', system-ui, -apple-system, sans-serif;
      font-size: 15px;
      line-height: 1.65;
      -webkit-font-smoothing: antialiased;
    }
    .article-content h1 { font-size: 1.7em; font-weight: 700; margin: 1.3em 0 0.5em; color: #f9fafb; line-height: 1.25; }
    .article-content h2 { font-size: 1.45em; font-weight: 700; margin: 1.3em 0 0.5em; color: #f9fafb; line-height: 1.3; }
    .article-content h3 { font-size: 1.2em; font-weight: 600; margin: 1.3em 0 0.5em; color: #f9fafb; line-height: 1.4; }
    .article-content p { margin: 0 0 1.25em; }
    .article-content a { color: #60a5fa; text-decoration: underline; }
    .article-content ul { list-style-type: disc; padding-left: 1.5em; margin: 0 0 1.25em; }
    .article-content ol { list-style-type: decimal; padding-left: 1.5em; margin: 0 0 1.25em; }
    .article-content li { margin-bottom: 0.5em; }
    .article-content blockquote {
      border-left: 4px solid #4b5563; padding: 0.5em 1em; margin: 1.5em 0;
      background: rgba(31, 41, 55, 0.5); border-radius: 0 0.5rem 0.5rem 0;
      font-style: italic; color: #9ca3af;
    }
    .article-content img { max-width: 100%; height: auto; border-radius: 0.5rem; margin: 1.5em 0; display: block; }
    .article-content strong, .article-content b { font-weight: 700; color: #f3f4f6; }
    .article-content em, .article-content i { font-style: italic; }
    .article-content pre {
      background: #030712; padding: 1em; border-radius: 0.5rem;
      overflow-x: auto; margin: 0 0 1.25em; border: 1px solid #374151;
    }
    .article-content code {
      background: rgba(55, 65, 81, 0.5); padding: 0.2em 0.4em;
      border-radius: 0.25rem; font-family: monospace; font-size: 0.875em; color: #e5e7eb;
    }
    .article-content hr { border: none; border-top: 1px solid #374151; margin: 2em 0; }
    .article-content .ql-align-center { text-align: center; }
    .article-content .ql-align-right { text-align: right; }
    .article-content .ql-align-justify { text-align: justify; }
    .article-content .ql-align-center img { display: inline-block; margin-left: auto; margin-right: auto; }
    .related { margin-top: 2em; border-top: 1px solid #374151; padding-top: 1.4em; }
    .related h2 { font-size: 1.25em; font-weight: 700; color: #f9fafb; margin: 0 0 1em; }
    .rel-card {
      display: block; background: #1f2937; border-radius: 12px; overflow: hidden;
      margin: 14px 0; text-decoration: none; border: 1px solid #1f2937;
    }
    .rel-card img { width: 100%; height: 132px; object-fit: cover; display: block; }
    .rel-card .t { padding: 12px 14px; color: #f9fafb; font-weight: 600; font-size: 14px; line-height: 1.35; }
  ''';

  final relatedHtml = related.isEmpty
      ? ''
      : '''
    <div class="related">
      <h2>Continue Reading</h2>
      ${related.map(_relatedCard).join()}
    </div>
  ''';

  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>$css</style>
</head>
<body>
<div class="article-content">
$contentHtml
</div>
$relatedHtml
<script>
  // Auto-height bridge: report the document height to the native WebView
  // host (EnclavdBridge channel) on load, on every image/font load (a
  // loaded asset changes the height after first paint) and on a few
  // delayed re-measures so the page settles to its final size.
  (function () {
    function report() {
      setTimeout(function () {
        try {
          EnclavdBridge.postMessage(String(document.documentElement.scrollHeight));
        } catch (e) {}
      }, 40);
    }
    document.addEventListener('load', report, true);
    window.addEventListener('resize', report);
    [250, 900, 2200].forEach(function (ms) { setTimeout(report, ms); });
  })();
</script>
</body>
</html>
''';
}

String _relatedCard(ArticleSummary a) {
  final cover = a.cover.isEmpty
      ? ''
      : '<img src="${_esc(a.cover)}" alt="">';
  return '''
<a class="rel-card" href="/article/${_esc(a.slug)}">
  $cover
  <div class="t">${_esc(a.title)}</div>
</a>
''';
}

/// HTML-escapes a plain-text value for injection into the document (titles,
/// slugs, cover paths). The article BODY is raw HTML by contract and is
/// intentionally NOT escaped by the caller.
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
