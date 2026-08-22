import 'api_client.dart';

/// A summary article row — the list card data (and the detail's related
/// items). Contract: api/v1/articles.php GET (web repo — deployed by the
/// user). `cover` is '' or a root-relative path ('/public/articles/x.jpg');
/// `published_date` is a DB UTC wall-clock string; `profile_picture_url`
/// is root-relative like every other avatar in the API.
class ArticleSummary {
  const ArticleSummary({
    required this.id,
    required this.slug,
    required this.title,
    required this.cover,
    required this.views,
    required this.publishedDate,
    required this.pinned,
    required this.authorId,
    required this.authorUsername,
    required this.authorAvatar,
    required this.personalityType,
    required this.rank,
  });

  final int id;
  final String slug;
  final String title;
  final String cover; // '' or root-relative '/public/articles/...'
  final int views;
  final String publishedDate; // DB UTC wall-clock 'YYYY-MM-DD HH:MM:SS'
  final bool pinned;
  final int authorId;
  final String authorUsername;
  final String authorAvatar; // root-relative
  final String? personalityType;
  final String rank;

  /// Absolute cover URL, or null when the article has no cover.
  String? coverUrl(String base) => cover.isEmpty ? null : '$base$cover';

  String avatarUrl(String base) => authorAvatar.startsWith('/')
      ? '$base$authorAvatar'
      : authorAvatar;

  factory ArticleSummary.fromJson(Map<String, dynamic> json) => ArticleSummary(
        id: (json['id'] as num?)?.toInt() ?? 0,
        slug: json['slug'] as String? ?? '',
        title: json['title'] as String? ?? '',
        cover: json['cover'] as String? ?? '',
        views: (json['views'] as num?)?.toInt() ?? 0,
        publishedDate: json['published_date'] as String? ?? '',
        pinned: json['pinned'] as bool? ?? false,
        authorId: (json['author_id'] as num?)?.toInt() ?? 0,
        authorUsername: json['username'] as String? ?? '',
        authorAvatar: json['profile_picture_url'] as String? ??
            '/assets/default-avatar.png',
        personalityType: json['personality_type'] as String?,
        rank: json['rank'] as String? ?? 'Member',
      );
}

/// The full article — the detail screen's data. `content` is the Quill HTML
/// exactly as stored (entities intact — the site decodes before echoing, a
/// WebView decodes at parse time; never decode it into a Text widget).
class Article {
  const Article({
    required this.summary,
    required this.content,
    required this.tags,
    required this.likeCount,
    required this.liked,
    required this.related,
  });

  final ArticleSummary summary;
  final String content; // HTML as stored — render as HTML, not plain text
  final List<String> tags;
  final int likeCount;
  final bool liked;
  final List<ArticleSummary> related; // "Continue Reading" (max 2)

  factory Article.fromJson(Map<String, dynamic> json) => Article(
        summary: ArticleSummary.fromJson(json),
        content: json['content'] as String? ?? '',
        tags: [
          for (final t in (json['tags'] as List<dynamic>? ?? const []))
            if (t is String) t,
        ],
        likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
        liked: json['liked'] as bool? ?? false,
        related: [
          for (final r in (json['related'] as List<dynamic>? ?? const []))
            if (r is Map<String, dynamic>) ArticleSummary.fromJson(r),
        ],
      );
}

/// The Updates list: pinned articles first, then the regular ones (the
/// site's articles.php split, both newest-first).
class ArticlesFeed {
  const ArticlesFeed({required this.pinned, required this.articles});

  final List<ArticleSummary> pinned;
  final List<ArticleSummary> articles;
}

/// ArticlesService — the native Updates screen over api/v1.
///
/// Contracts (api/v1/articles.php, web repo):
///   GET  /api/v1/articles          → {success, pinned:[...], articles:[...]}
///   GET  /api/v1/articles?slug=X   → {success, article:{...}} (404 unknown)
///   POST /api/v1/articles          → {action:'toggle_like', article_id} —
///        JSON + CSRF → {success, liked, like_count}
///
/// Reads are public (the site's article pages are public); the detail's
/// `liked` is false for guests. The detail GET mirrors article.php's view
/// rule (one increment per session per 24h) — reads never spam the counter.
class ArticlesService {
  ArticlesService(this._api);

  final ApiClient _api;

  Future<ArticlesFeed> list() async {
    final json = await _api.getJson('/api/v1/articles');
    List<ArticleSummary> parse(String key) => [
          for (final item in (json[key] as List<dynamic>? ?? const []))
            if (item is Map<String, dynamic>) ArticleSummary.fromJson(item),
        ];
    return ArticlesFeed(pinned: parse('pinned'), articles: parse('articles'));
  }

  Future<Article> fetch(String slug) async {
    final json = await _api.getJson('/api/v1/articles',
        query: <String, String>{'slug': slug});
    final article = json['article'];
    if (article is! Map<String, dynamic>) {
      throw const ApiException('Invalid response from server');
    }
    return Article.fromJson(article);
  }

  /// Toggles the current user's like on an article; returns (liked, count).
  Future<(bool, int)> toggleLike(int articleId) async {
    final json = await _api.postJson('/api/v1/articles', <String, dynamic>{
      'action': 'toggle_like',
      'article_id': articleId,
    });
    return (
      json['liked'] as bool? ?? false,
      (json['like_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// The newest article id — the new-articles badge check. The API answers
  /// with a cheap MAX(id) (no joins, no list payload), so the launch-time
  /// check costs one tiny request instead of shipping the whole feed.
  Future<int> latestId() async {
    final json = await _api.getJson('/api/v1/articles',
        query: <String, String>{'latest': '1'});
    return (json['latest_id'] as num?)?.toInt() ?? 0;
  }

  /// SharedPreferences key holding the newest article id the user has seen
  /// (written on launch baseline and whenever the Updates list loads).
  static const String seenIdPrefKey = 'last_seen_article_id';
}
