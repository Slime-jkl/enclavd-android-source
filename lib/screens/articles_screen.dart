import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/articles_service.dart';
import '../api/messages_service.dart'; // parseDbTime (DB UTC wall-clock)
import '../config/app_config.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/enclavd_image.dart';
import '../widgets/pinned_badge.dart';
import '../widgets/shimmer.dart';
import 'article_detail_screen.dart';

/// The native Updates screen — the site's /articles (articles.php) as a
/// modern app: pinned articles in their own section (site: the pinned grid
/// first), then the regular list. Site parity:
///  - cards carry the cover, title, author avatar + username, published
///    date ("M j, Y") and the view count (fa-eye, comma-formatted);
///  - pinned cards get the red fire "PINNED" chip;
///  - tap → the native ArticleDetailScreen (the site's /article/<slug>).
/// Modern-app look: rounded card rows with gaps instead of full-width
/// dividers, shimmer skeletons on first load, pull-to-refresh.
class ArticlesScreen extends StatefulWidget {
  const ArticlesScreen({
    super.key,
    required this.articles,
    this.detailBuilder,
  });

  final ArticlesService articles;

  /// Test seam — replaces the pushed detail screen (the real one mounts a
  /// WebView, a platform view that does not exist under `flutter test`).
  final Widget Function(String slug)? detailBuilder;

  @override
  State<ArticlesScreen> createState() => _ArticlesScreenState();
}

class _ArticlesScreenState extends State<ArticlesScreen> {
  List<ArticleSummary> _pinned = const [];
  List<ArticleSummary> _articles = const [];
  bool _loading = true;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final feed = await widget.articles.list();
      if (!mounted) return;
      setState(() {
        _pinned = feed.pinned;
        _articles = feed.articles;
        _loading = false;
        _loaded = true;
      });
      // The user has now seen the newest articles — advance the badge
      // baseline so the Updates dot clears until something new appears.
      unawaited(_storeSeenId(feed));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Persists the newest article id from the loaded feed (the launch-check
  /// baseline in the feed screen compares against this).
  Future<void> _storeSeenId(ArticlesFeed feed) async {
    var maxId = 0;
    for (final a in feed.pinned) {
      if (a.id > maxId) maxId = a.id;
    }
    for (final a in feed.articles) {
      if (a.id > maxId) maxId = a.id;
    }
    if (maxId <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(ArticlesService.seenIdPrefKey, maxId);
  }

  void _open(ArticleSummary a) {
    final builder = widget.detailBuilder;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => builder != null
          ? builder(a.slug)
          : ArticleDetailScreen(articles: widget.articles, slug: a.slug),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (!_loaded && _loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _ArticleCardSkeleton(),
          _ArticleCardSkeleton(),
          _ArticleCardSkeleton(),
        ],
      );
    }
    if (_error != null && !_loaded) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FaIcon(FontAwesomeIcons.triangleExclamation,
                  color: EnclavdColors.likeActive, size: 28),
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(color: EnclavdColors.textSecondary)),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_pinned.isEmpty && _articles.isEmpty) {
      // Site empty state (articles.php "No Articles Yet").
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(FontAwesomeIcons.newspaper,
                color: EnclavdColors.textSecondary, size: 28),
            SizedBox(height: 10),
            Text('No articles yet',
                style: TextStyle(color: EnclavdColors.textSecondary)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: EnclavdColors.link,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (_pinned.isNotEmpty) ...[
            const _SectionLabel('Pinned'),
            for (final a in _pinned) _ArticleCard(article: a, onTap: () => _open(a)),
          ],
          if (_articles.isNotEmpty) ...[
            const _SectionLabel('Latest'),
            for (final a in _articles)
              _ArticleCard(article: a, onTap: () => _open(a)),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Uppercase section label between the Pinned and Latest groups (the same
/// label style as the user menu drawer's sections).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: EnclavdColors.textSecondary,
        ),
      ),
    );
  }
}

/// Modern card row: rounded card, cover image, title, author + date + views
/// meta line; pinned cards carry the red fire chip on the cover.
class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article, required this.onTap});

  final ArticleSummary article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = article;
    final cover = a.coverUrl(AppConfig.apiBaseUrl);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cover != null)
                Stack(
                  children: [
                    // A tight full-width box: EnclavdImage must NOT get
                    // width: double.infinity itself (its cacheWidth math
                    // .ceil()s the width — Infinity crashes).
                    SizedBox(
                      width: double.infinity,
                      height: 170,
                      child: EnclavdImage(
                        cover,
                        fit: BoxFit.cover,
                        errorAsset: 'assets/images/no-image.jpg',
                      ),
                    ),
                    if (a.pinned)
                      const Positioned(top: 10, left: 10, child: PinnedBadge()),
                  ],
                )
              else if (a.pinned)
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Align(
                      alignment: Alignment.centerLeft, child: PinnedBadge()),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: EnclavdColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        EnclavdAvatar(
                          size: 18,
                          url: a.avatarUrl(AppConfig.apiBaseUrl),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            a.authorUsername,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: EnclavdColors.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('•',
                            style: TextStyle(
                                fontSize: 11,
                                color: EnclavdColors.textSecondary)),
                        const SizedBox(width: 6),
                        Text(_formatDate(a.publishedDate),
                            style: const TextStyle(
                                fontSize: 12,
                                color: EnclavdColors.textSecondary)),
                        const SizedBox(width: 6),
                        const Text('•',
                            style: TextStyle(
                                fontSize: 11,
                                color: EnclavdColors.textSecondary)),
                        const SizedBox(width: 6),
                        const FaIcon(FontAwesomeIcons.eye,
                            size: 11, color: EnclavdColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(_formatViews(a.views),
                            style: const TextStyle(
                                fontSize: 12,
                                color: EnclavdColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// First-load skeleton — the site's card-skeleton-layer ported to a card.
class _ArticleCardSkeleton extends StatelessWidget {
  const _ArticleCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.all(Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ShimmerBox(width: double.infinity, height: 170, borderRadius: 0),
            Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(width: double.infinity, height: 15),
                  SizedBox(height: 6),
                  ShimmerBox(width: 150, height: 15),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      ShimmerBox(width: 18, height: 18, shape: BoxShape.circle),
                      SizedBox(width: 8),
                      ShimmerBox(width: 130, height: 12),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The site's list date: date('M j, Y', strtotime(...)) on the DB wall-clock.
String _formatDate(String dbUtc) {
  final t = parseDbTime(dbUtc);
  if (t == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[t.month - 1]} ${t.day}, ${t.year}';
}

/// The site's view counts: number_format() → thousands with commas.
String _formatViews(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
