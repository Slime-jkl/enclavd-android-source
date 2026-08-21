import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/api/articles_service.dart';
import 'package:enclavd/utils/article_html.dart';

ArticleSummary _related(String slug, String title, {String cover = ''}) =>
    ArticleSummary(
      id: 1,
      slug: slug,
      title: title,
      cover: cover,
      views: 0,
      publishedDate: '2026-06-04 16:12:02',
      pinned: false,
      authorId: 1,
      authorUsername: 'Dev',
      authorAvatar: '/public/avatars/dev.png',
      personalityType: null,
      rank: 'Member',
    );

void main() {
  test('injects the content as-is and escapes related metadata', () {
    final html = buildArticleHtml(
      contentHtml: '<p>Hello &amp; <strong>world</strong></p>',
      related: [
        _related('a&b', 'Title <script>alert(1)</script>',
            cover: '/public/articles/c.jpg'),
      ],
      baseUrl: 'https://enclavd.com',
    );

    expect(html, contains('<p>Hello &amp; <strong>world</strong></p>'),
        reason: 'the stored HTML body is injected verbatim');
    expect(html, contains('href="/article/a&amp;b"'),
        reason: 'slugs are escaped for the href attribute');
    expect(html, contains('Title &lt;script&gt;alert(1)&lt;/script&gt;'),
        reason: 'titles are escaped — never raw HTML');
    expect(html, contains('src="/public/articles/c.jpg"'));
    expect(html, contains('Continue Reading'));
    expect(html, contains("url('assets/fonts/Montserrat/"),
        reason: 'the site font is self-hosted under assets/fonts');
    expect(html, contains('EnclavdBridge'),
        reason: 'the auto-height measurement script ships with every doc');
  });

  test('omits the Continue Reading section when there is nothing related',
      () {
    final html = buildArticleHtml(
      contentHtml: '<p>Only one article.</p>',
      related: const [],
      baseUrl: 'https://enclavd.com',
    );
    expect(html, contains('Only one article.'));
    expect(html, isNot(contains('Continue Reading')));
    expect(html, isNot(contains('<div class="related">')));
  });

  test('cover-less related cards skip the img tag', () {
    final html = buildArticleHtml(
      contentHtml: '<p>x</p>',
      related: [_related('plain', 'No cover')],
      baseUrl: 'https://enclavd.com',
    );
    expect(html, isNot(contains('<img')));
    expect(html, contains('<div class="t">No cover</div>'));
  });
}
