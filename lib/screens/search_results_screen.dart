import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../api/search_service.dart';
import '../config/app_config.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/personality_chip.dart';
import '../widgets/rank_badge.dart';
import '../widgets/shimmer.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';

/// Search results — the screen the notification drawer's search bar
/// lands on. Fetches api/v1/search?q=…&format=json (posts, users,
/// comments in one structured payload) and renders them grouped by type
/// (Members / Posts / Comments).
///
/// Loading: a shimmer skeleton of the exact row layout (the drawer
/// precedent — never a bare spinner). Results respect the site's visual
/// identity natively: avatar with personality border, username in RANK
/// color, rank badge + personality chip, content preview and stats.
/// Taps: users → ProfileScreen, posts/comments → PostDetailScreen.
class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({
    super.key,
    required this.search,
    required this.query,
  });

  final SearchService search;
  final String query;

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  List<SearchResult>? _results; // null = loading
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await widget.search.search(widget.query);
      if (!mounted) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Search failed. Check your connection and retry.');
    }
  }

  void _open(SearchResult r) {
    if (r.type == 'user') {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ProfileScreen(userId: r.userId),
      ));
      return;
    }
    // Posts AND comments deep-link to the post (the site's search rows
    // point comments at /feed/post/<post_id> too).
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PostDetailScreen(postId: r.type == 'comment'
          ? r.postId
          : r.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Search: ${widget.query}')),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
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
    final results = _results;
    if (results == null) {
      // Shimmer the page until the results arrive — same skeleton family
      // as the rest of the app (avatar circle + lines per row, section
      // label bars between groups).
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _SearchRowSkeleton(),
          _SearchRowSkeleton(),
          _SearchRowSkeleton(),
          _SearchRowSkeleton(),
          _SearchRowSkeleton(),
          _SearchRowSkeleton(),
        ],
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FaIcon(FontAwesomeIcons.magnifyingGlass,
                color: EnclavdColors.textSecondary, size: 28),
            const SizedBox(height: 10),
            Text('No results for "${widget.query}"',
                style: const TextStyle(color: EnclavdColors.textSecondary)),
          ],
        ),
      );
    }
    // Group by type (the API already orders user → post → comment; keep
    // the sections stable even if the order ever changes).
    final users = results.where((r) => r.type == 'user').toList();
    final posts = results.where((r) => r.type == 'post').toList();
    final comments = results.where((r) => r.type == 'comment').toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (users.isNotEmpty) ...[
            const _SectionHeader('Members'),
            for (final r in users) _ResultRow(result: r, onTap: () => _open(r)),
          ],
          if (posts.isNotEmpty) ...[
            const _SectionHeader('Posts'),
            for (final r in posts) _ResultRow(result: r, onTap: () => _open(r)),
          ],
          if (comments.isNotEmpty) ...[
            const _SectionHeader('Comments'),
            for (final r in comments)
              _ResultRow(result: r, onTap: () => _open(r)),
          ],
        ],
      ),
    );
  }
}

/// Uppercase section label (Members / Posts / Comments) — same language
/// as the user menu drawer's grouped sections.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
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

/// One search result row: avatar (personality border), username in the
/// RANK color, rank badge + personality chip, then the type-specific
/// preview (bio/posts count, post text + like/comment stats, comment
/// text + the parent post line).
class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result, required this.onTap});

  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final personality = PersonalityColors.forType(r.personalityType);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EnclavdAvatar(
              size: 40,
              url: r.avatar.startsWith('/')
                  ? '${AppConfig.apiBaseUrl}${r.avatar}'
                  : r.avatar,
              borderColor: personality ?? EnclavdColors.border,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Username (rank color) + rank badge + personality chip.
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.username,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: r.rank == 'Blocked'
                                ? RankColors.forRank('Blocked')
                                : RankColors.forRank(r.rank),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      RankBadge(rank: r.rank),
                      if (personality != null) ...[
                        const SizedBox(width: 6),
                        PersonalityChip(type: r.personalityType),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  _Subtitle(result: r),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Type-specific preview under the identity row.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    const secondary = TextStyle(
        fontSize: 13, color: EnclavdColors.textSecondary, height: 1.35);
    switch (r.type) {
      case 'user':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.content.isNotEmpty)
              Text(r.content, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: secondary),
            const SizedBox(height: 2),
            Text('${r.stats['posts'] ?? 0} posts', style: secondary),
          ],
        );
      case 'post':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.content, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: secondary),
            const SizedBox(height: 3),
            Row(
              children: [
                const FaIcon(FontAwesomeIcons.heart,
                    size: 11, color: EnclavdColors.textSecondary),
                const SizedBox(width: 4),
                Text('${r.stats['likes'] ?? 0}',
                    style: const TextStyle(
                        fontSize: 12, color: EnclavdColors.textSecondary)),
                const SizedBox(width: 12),
                const FaIcon(FontAwesomeIcons.comment,
                    size: 11, color: EnclavdColors.textSecondary),
                const SizedBox(width: 4),
                Text('${r.stats['comments'] ?? 0}',
                    style: const TextStyle(
                        fontSize: 12, color: EnclavdColors.textSecondary)),
              ],
            ),
          ],
        );
      default: // comment
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.content, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: secondary),
            if (r.postContent.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text('On: ${r.postContent}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      color: EnclavdColors.textSecondary,
                      fontStyle: FontStyle.italic)),
            ],
          ],
        );
    }
  }
}

/// Loading skeleton: avatar circle + two lines, shaped like the real
/// rows so the page visibly loads (never a bare spinner).
class _SearchRowSkeleton extends StatelessWidget {
  const _SearchRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(width: 40, height: 40, shape: BoxShape.circle),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 130, height: 14),
                SizedBox(height: 8),
                ShimmerBox(width: double.infinity, height: 12),
                SizedBox(height: 6),
                ShimmerBox(width: 90, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
