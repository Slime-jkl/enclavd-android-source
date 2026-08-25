import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/auth_service.dart'; // resolveMediaUrl
import '../api/domains_service.dart';
import '../api/messages_service.dart'; // parseDbTime (DB UTC wall-clock)
import '../config/app_config.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import '../utils/domain_icons.dart';
import '../widgets/enclavd_avatar.dart';
import '../widgets/post_card.dart'; // relativeTime
import '../widgets/shimmer.dart';
import 'domain_thread_screen.dart';
import '../services/analytics_service.dart';

/// Thread list for one domain category (site: /domain category view).
///
/// Shows the category header (icon + name + description, breadcrumb-style
/// "Domains / Category") over its threads — posts ordered by newest
/// activity, INCLUDING subcategory posts (site: get_domain_ids_with_children).
/// Thread rows are the site's thread_row port: avatar, excerpt-as-title,
/// author + date, then comment/like counts + last activity. Infinite
/// scroll via offset pagination; tap → the forum thread view.
class DomainCategoryScreen extends StatefulWidget {
  const DomainCategoryScreen({
    super.key,
    required this.domains,
    required this.category,
    this.threadBuilder,
  });

  final DomainsService domains;
  final DomainCategory category;

  /// Test seam — replaces the pushed thread screen.
  final Widget Function(DomainThread thread)? threadBuilder;

  @override
  State<DomainCategoryScreen> createState() => _DomainCategoryScreenState();
}

class _DomainCategoryScreenState extends State<DomainCategoryScreen> {
  final List<DomainThread> _threads = [];
  final _scrollController = ScrollController();
  DomainCategory _category = const DomainCategory(
      id: 0,
      name: '',
      slug: '',
      displayOrder: 0,
      icon: '',
      color: '',
      postCount: 0);
  bool _loading = false;
  bool _initialLoadDone = false;
  bool _hasMore = false;
  int _offset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    trackScreen('/forum');
    _category = widget.category;
    _scrollController.addListener(_onScroll);
    _loadFirst();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || !_initialLoadDone) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadNext();
    }
  }

  Future<void> _loadFirst() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final page = await widget.domains.threads(_category.id, offset: 0);
      if (!mounted) return;
      setState(() {
        _threads
          ..clear()
          ..addAll(page.threads);
        // The API's category row is the source of truth for the header
        // (fresh icon/color/description); keep the navigated name as a
        // fallback when the row is empty.
        if (page.category.id != 0) _category = page.category;
        _hasMore = page.hasMore;
        _offset = page.threads.length;
        _loading = false;
        _initialLoadDone = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        if (_threads.isEmpty) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialLoadDone = true;
        if (_threads.isEmpty) _error = 'Failed to load discussions.';
      });
    }
  }

  Future<void> _loadNext() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final page = await widget.domains.threads(_category.id, offset: _offset);
      if (!mounted) return;
      setState(() {
        _threads.addAll(page.threads);
        _hasMore = page.hasMore;
        _offset += page.threads.length;
        _loading = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _open(DomainThread thread) {
    final builder = widget.threadBuilder;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => builder != null
          ? builder(thread)
          : DomainThreadScreen(
              domains: widget.domains,
              postId: thread.post.id,
              breadcrumbName: _category.name,
            ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Site breadcrumb: Domains / <category>.
        title: Text(_category.name),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (!_initialLoadDone && _loading) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _CategoryHeaderSkeleton(),
          _ThreadRowSkeleton(),
          _ThreadRowSkeleton(),
          _ThreadRowSkeleton(),
        ],
      );
    }
    if (_error != null && _threads.isEmpty) {
return ErrorView(message: _error!, onRetry: _loadFirst);
    }
    if (_threads.isEmpty) {
      // Site empty state (category view: "No discussions in this category
      // yet.").
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _CategoryHeader(category: _category),
          const Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              children: [
                FaIcon(FontAwesomeIcons.comments,
                    color: EnclavdColors.textSecondary, size: 28),
                SizedBox(height: 10),
                Text('No discussions in this category yet',
                    style: TextStyle(color: EnclavdColors.textSecondary)),
              ],
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirst,
      color: EnclavdColors.link,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _threads.length + (_loading ? 1 : 0) + 1,
        itemBuilder: (context, index) {
          if (index == 0) return _CategoryHeader(category: _category);
          final threadIndex = index - 1;
          if (threadIndex >= _threads.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: ShimmerBox(width: 160, height: 22)),
            );
          }
          final thread = _threads[threadIndex];
          return _ThreadRow(
            key: ValueKey(thread.post.id),
            thread: thread,
            onTap: () => _open(thread),
          );
        },
      ),
    );
  }
}

/// Category header block (site: breadcrumb + icon + name + description).
class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category});

  final DomainCategory category;

  @override
  Widget build(BuildContext context) {
    final accent = domainColorFromHex(category.color);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: FaIcon(domainIconFor(category.icon), size: 19, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: EnclavdColors.textPrimary,
                  ),
                ),
                if (category.description != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    category.description!,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: EnclavdColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One thread row — the site's thread_row port: avatar (personality
/// border), excerpt-as-title (first ~120 chars of the decoded content),
/// author + posted date, then comment/like counts + last activity.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({super.key, required this.thread, required this.onTap});

  final DomainThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final post = thread.post;
    final personality = PersonalityColors.forType(post.personalityType);
    final excerpt = _excerpt(post.content);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EnclavdAvatar(
                  size: 38,
                  url: resolveMediaUrl(AppConfig.apiBaseUrl,
                      avatarPath: post.profilePictureUrl),
                  borderColor: personality,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thread title = the excerpt (site: first line).
                      Text(
                        excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: EnclavdColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Meta: author (rank color) · relative date.
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              post.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: post.isBlocked
                                    ? RankColors.forRank('Blocked')
                                    : RankColors.forRank(post.rank),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· ${relativeTime(post.createdAt)}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: EnclavdColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Stats: comments + likes + last activity.
                      Row(
                        children: [
                          const FaIcon(FontAwesomeIcons.comments,
                              size: 12, color: EnclavdColors.textSecondary),
                          const SizedBox(width: 4),
                          Text('${post.commentCount}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: EnclavdColors.textSecondary)),
                          const SizedBox(width: 14),
                          const FaIcon(FontAwesomeIcons.heart,
                              size: 12, color: EnclavdColors.textSecondary),
                          const SizedBox(width: 4),
                          Text('${post.likeCount}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: EnclavdColors.textSecondary)),
                          if (_lastActivity != null) ...[
                            const SizedBox(width: 14),
                            const FaIcon(FontAwesomeIcons.clock,
                                size: 12, color: EnclavdColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(_lastActivity!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: EnclavdColors.textSecondary)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const FaIcon(FontAwesomeIcons.chevronRight,
                    size: 12, color: EnclavdColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Last activity = the newest reply time, else the post time (the site's
  /// $lastActivity = last_reply_at ?? created_at), as a short relative
  /// string like "2h" / "3d" (relativeTime's compact form).
  String? get _lastActivity {
    final raw = thread.lastReplyAt ?? thread.post.createdAt;
    final t = parseDbTime(raw);
    if (t == null) return null;
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo';
    return '${diff.inDays ~/ 365}y';
  }
}

/// The site's excerpt rule (thread_row.php): first 120 chars of the
/// decoded content, ellipsis when truncated. '(no content)' for empty.
String _excerpt(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return '(no content)';
  return trimmed.length > 120 ? '${trimmed.substring(0, 120)}…' : trimmed;
}

/// Category header skeleton (icon block + two text lines).
class _CategoryHeaderSkeleton extends StatelessWidget {
  const _CategoryHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(width: 44, height: 44, borderRadius: 12),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 140, height: 18),
                SizedBox(height: 6),
                ShimmerBox(width: 200, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton of a thread row (avatar + excerpt lines + stats).
class _ThreadRowSkeleton extends StatelessWidget {
  const _ThreadRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.all(Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(width: 38, height: 38, shape: BoxShape.circle),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: double.infinity, height: 13),
                    SizedBox(height: 6),
                    ShimmerBox(width: 190, height: 13),
                    SizedBox(height: 8),
                    ShimmerBox(width: 150, height: 11),
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
