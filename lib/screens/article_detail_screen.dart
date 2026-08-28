import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api_client.dart';
import '../api/articles_service.dart';
import '../api/messages_service.dart'; // parseDbTime (DB UTC wall-clock)
import '../config/app_config.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import '../utils/article_html.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/enclavd_image.dart';
import '../widgets/personality_chip.dart';
import '../widgets/pinned_badge.dart';
import '../widgets/rank_badge.dart';
import '../widgets/shimmer.dart';
import 'profile_screen.dart';
import '../services/analytics_service.dart';

class ArticleDetailScreen extends StatefulWidget {
  const ArticleDetailScreen({
    super.key,
    required this.articles,
    required this.slug,
    this.bodyBuilder,
  });

  final ArticlesService articles;
  final String slug;

  /// Test seam: replaces the WebView body under flutter test.
  final Widget Function(String html, String baseUrl)? bodyBuilder;

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  Article? _article;
  String? _error;

  // Like state: optimistic mirror of the server row.
  bool _liked = false;
  int _likeCount = 0;
  bool _likeBusy = false;

  @override
  void initState() {
    super.initState();
    trackScreen('/article');
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final article = await widget.articles.fetch(widget.slug);
      if (!mounted) return;
      setState(() {
        _article = article;
        _liked = article.liked;
        _likeCount = article.likeCount;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _toggleLike() async {
    final article = _article;
    if (article == null || _likeBusy) return;
    _likeBusy = true;
    // Optimistic flip (the site's setArticleHeart before the fetch).
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    try {
      final (liked, count) =
          await widget.articles.toggleLike(article.summary.id);
      if (!mounted) return;
      // Reconcile with the server's truth.
      setState(() {
        _liked = liked;
        _likeCount = count;
      });
    } catch (_) {
      if (!mounted) return;
      // Rollback + toast on failure (the site's like_article failure path).
      setState(() {
        _liked = !_liked;
        _likeCount += _liked ? 1 : -1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not like this article.')),
      );
    } finally {
      _likeBusy = false;
    }
  }

  void _openRelatedBySlug(String slug) {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ArticleDetailScreen(
        articles: widget.articles,
        slug: slug,
        bodyBuilder: widget.bodyBuilder,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final title = _article?.summary.title;
    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? 'Article',
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null && _article == null) {
return ErrorView(message: _error!, onRetry: _load);
    }
    final article = _article;
    if (article == null) {
      return const _DetailSkeleton();
    }
    final html = buildArticleHtml(
      contentHtml: article.content,
      related: article.related,
      baseUrl: AppConfig.apiBaseUrl,
    );
    // The whole page scrolls as one; the WebView is sized to its content.
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _ArticleHero(article: article),
        _AuthorRow(
          article: article,
          liked: _liked,
          likeCount: _likeCount,
          onLike: _toggleLike,
        ),
        if (article.tags.isNotEmpty) _TagChips(tags: article.tags),
        const Divider(height: 1, color: EnclavdColors.divider),
        _buildBodyView(html),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _buildBodyView(String html) {
    final bodyBuilder = widget.bodyBuilder;
    if (bodyBuilder != null) {
      return bodyBuilder(html, AppConfig.apiBaseUrl);
    }
    return _ArticleBodyWebView(
      html: html,
      baseUrl: AppConfig.apiBaseUrl,
      onArticleLink: _openRelatedBySlug,
      onExternalLink: (uri) => launchUrl(uri,
          mode: LaunchMode.externalApplication),
    );
  }
}

class _ArticleHero extends StatelessWidget {
  const _ArticleHero({required this.article});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final a = article.summary;
    final cover = a.coverUrl(AppConfig.apiBaseUrl);
    if (cover == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (a.pinned) ...[
              const PinnedBadge(),
              const SizedBox(height: 10),
            ],
            Text(
              a.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: EnclavdColors.textPrimary,
                height: 1.25,
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 250,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          EnclavdImage(
            cover,
            fit: BoxFit.cover,
            errorAsset: 'assets/images/no-image.jpg',
          ),
          // The cover fades into the page color so the title always sits on it.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 125, // the bottom HALF of the 250px hero
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.5, 1],
                    colors: [
                      EnclavdColors.background.withValues(alpha: 0),
                      EnclavdColors.background.withValues(alpha: 0.5),
                      EnclavdColors.background,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // View chip (article.php: the primaryCardColor pill top-right).
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: EnclavdColors.card,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FaIcon(FontAwesomeIcons.eye,
                      size: 12, color: EnclavdColors.textPrimary),
                  const SizedBox(width: 6),
                  Text(
                    formatViews(a.views),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: EnclavdColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (a.pinned)
            const Positioned(top: 12, left: 12, child: PinnedBadge()),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Text(
              a.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.25,
                shadows: [
                  Shadow(color: Colors.black54, blurRadius: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  const _AuthorRow({
    required this.article,
    required this.liked,
    required this.likeCount,
    required this.onLike,
  });

  final Article article;
  final bool liked;
  final int likeCount;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final a = article.summary;
    final rankColor = RankColors.forRank(a.rank);
    final personality = PersonalityColors.forType(a.personalityType);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Row(
        children: [
          EnclavdAvatar(
            size: 42,
            url: a.avatarUrl(AppConfig.apiBaseUrl),
            borderColor: personality,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rank badge above the username.
                RankBadge(rank: a.rank),
                const SizedBox(height: 5),
                // Tapping the identity block opens the author's profile.
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProfileScreen(userId: a.authorId),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            a.authorUsername,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: rankColor,
                            ),
                          ),
                        ),
                        if (a.personalityType != null) ...[
                          const SizedBox(width: 6),
                          PersonalityChip(type: a.personalityType!),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Below the username: ONLY the published date.
                Text(
                  'Published on ${formatDateFull(a.publishedDate)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: EnclavdColors.textSecondary),
                ),
              ],
            ),
          ),
          // The site's article heart: outline -> filled on like.
          InkWell(
            onTap: onLike,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FaIcon(
                    liked
                        ? FontAwesomeIcons.solidHeart
                        : FontAwesomeIcons.heart,
                    size: 22,
                    color: liked
                        ? EnclavdColors.likeActive
                        : EnclavdColors.textSecondary,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatViews(likeCount),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: liked
                          ? EnclavdColors.likeActive
                          : EnclavdColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChips extends StatelessWidget {
  const _TagChips({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in tags)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: EnclavdColors.cardSecondary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FaIcon(FontAwesomeIcons.hashtag,
                      size: 10, color: EnclavdColors.link),
                  const SizedBox(width: 5),
                  Text(
                    tag,
                    style: const TextStyle(
                        fontSize: 11, color: EnclavdColors.textPrimary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ArticleBodyWebView extends StatefulWidget {
  const _ArticleBodyWebView({
    required this.html,
    required this.baseUrl,
    required this.onArticleLink,
    required this.onExternalLink,
  });

  final String html;
  final String baseUrl;
  final void Function(String slug) onArticleLink;
  final void Function(Uri uri) onExternalLink;

  @override
  State<_ArticleBodyWebView> createState() => _ArticleBodyWebViewState();
}

class _ArticleBodyWebViewState extends State<_ArticleBodyWebView> {
  int _height = 0;

  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(EnclavdColors.background)
    ..addJavaScriptChannel('EnclavdBridge', onMessageReceived: _onMeasure)
    ..setNavigationDelegate(NavigationDelegate(
      onPageFinished: (_) => _measure(),
      onNavigationRequest: _onNavigationRequest,
    ))
    ..loadHtmlString(widget.html, baseUrl: widget.baseUrl);

  void _onMeasure(JavaScriptMessage message) {
    if (!mounted) return;
    final h = int.tryParse(message.message.trim());
    if (h == null || h <= 0 || h == _height) return;
    setState(() => _height = h);
  }

  void _measure() {
    _controller
        .runJavaScriptReturningResult('document.documentElement.scrollHeight')
        .then((value) {
      var raw = '$value'.trim();
      if (raw.length >= 2 &&
          raw.startsWith('"') &&
          raw.endsWith('"')) {
        raw = raw.substring(1, raw.length - 1);
      }
      final h = int.tryParse(raw);
      if (h != null && h > 0) _onMeasure(JavaScriptMessage(message: '$h'));
    }).catchError((_) {});
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.parse(request.url);
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final base = Uri.parse(widget.baseUrl);
      if (uri.host == base.host && uri.path.startsWith('/article/')) {
        final slug = uri.path.substring('/article/'.length).split('/').first;
        if (slug.isNotEmpty) widget.onArticleLink(slug);
      } else {
        widget.onExternalLink(uri);
      }
    }
    // Everything else (in-page anchors, data: URLs) stays put.
    return NavigationDecision.prevent;
  }

  @override
  Widget build(BuildContext context) {
    // Always mounted: a conditional mount deadlocks the measurement.
    final height = _height > 0 ? _height.toDouble() : 220.0;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_height <= 0)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: const [
        ShimmerBox(width: double.infinity, height: 250, borderRadius: 0),
        Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: double.infinity, height: 18),
              SizedBox(height: 8),
              ShimmerBox(width: 180, height: 18),
              SizedBox(height: 18),
              Row(
                children: [
                  ShimmerBox(width: 42, height: 42, shape: BoxShape.circle),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(width: 120, height: 14),
                      SizedBox(height: 6),
                      ShimmerBox(width: 90, height: 11),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The site's detail date: jS F Y h:i A on the DB wall-clock.
String formatDateFull(String dbUtc) {
  final t = parseDbTime(dbUtc);
  if (t == null) return '';
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  final d = t.day;
  final suffix = switch (d % 100) {
    11 || 12 || 13 => 'th',
    _ => switch (d % 10) {
        1 => 'st',
        2 => 'nd',
        3 => 'rd',
        _ => 'th',
      },
  };
  final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  final mm = t.minute.toString().padLeft(2, '0');
  return '$d$suffix ${months[t.month - 1]} ${t.year} $h12:$mm $ampm';
}

/// The site's number_format(): thousands with commas.
String formatViews(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
