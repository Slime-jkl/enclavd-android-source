import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/domains_service.dart';
import '../api/social_service.dart';
import '../theme/enclavd_theme.dart';
import '../utils/domain_icons.dart';
import '../widgets/domain_thread_row.dart';
import '../widgets/error_view.dart';
import '../widgets/shimmer.dart';
import 'domain_thread_screen.dart';

/// The Domains tab home - mirrors the site's new board: squared domain
/// filter buttons at the top and a latest-posts feed below (newest
/// activity first). Selecting a chip filters the feed to that domain and
/// its subcategories; "All" shows every domain's posts.
class DomainsScreen extends StatefulWidget {
  const DomainsScreen({
    super.key,
    required this.domains,
    this.social,
    this.threadBuilder,
  });

  final DomainsService domains;
  final SocialService? social;

  /// Test seam: replaces the pushed thread screen.
  final Widget Function(DomainThread thread)? threadBuilder;

  @override
  State<DomainsScreen> createState() => _DomainsScreenState();
}

class _DomainsScreenState extends State<DomainsScreen> {
  List<DomainCategory> _categories = const [];
  bool _chipsLoaded = false;

  int? _selectedId;
  final List<DomainThread> _threads = [];
  final _scrollController = ScrollController();
  bool _loading = false;
  bool _initialLoadDone = false;
  bool _hasMore = false;
  int _offset = 0;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadChips();
    _loadFeed(reset: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChips() async {
    try {
      final flat = await widget.domains.board();
      if (!mounted) return;
      setState(() {
        _categories = flat;
        _chipsLoaded = true;
      });
    } on ApiException {
      // Chips are secondary; the feed still works without them.
      if (!mounted) return;
      setState(() => _chipsLoaded = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _chipsLoaded = true);
    }
  }

  void _select(int? id) {
    if (_selectedId == id) return;
    setState(() {
      _selectedId = id;
      _threads.clear();
      _initialLoadDone = false;
      _error = null;
    });
    _loadFeed(reset: true);
  }

  void _onScroll() {
    if (_loading || !_initialLoadDone) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadFeed(reset: false);
    }
  }

  Future<void> _loadFeed({required bool reset}) async {
    if (_loading || (!reset && !_hasMore)) return;
    setState(() {
      _loading = true;
      if (reset) _error = null;
    });
    try {
      final page = await widget.domains.feed(
        domainId: _selectedId,
        offset: reset ? 0 : _offset,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _threads
            ..clear()
            ..addAll(page.threads);
          _offset = page.threads.length;
        } else {
          _threads.addAll(page.threads);
          _offset += page.threads.length;
        }
        _hasMore = page.hasMore;
        _total = page.total;
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
        if (_threads.isEmpty) _error = 'Failed to load posts.';
      });
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
              breadcrumbName: thread.domainName,
              social: widget.social,
            ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    if (!_initialLoadDone && _loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _ChipsSkeleton(),
          _FeedHeaderSkeleton(),
          DomainThreadRowSkeleton(),
          DomainThreadRowSkeleton(),
          DomainThreadRowSkeleton(),
        ],
      );
    }
    if (_error != null && _threads.isEmpty) {
      return ErrorView(message: _error!, onRetry: () => _loadFeed(reset: true));
    }
    return RefreshIndicator(
      onRefresh: () => _loadFeed(reset: true),
      color: EnclavdColors.link,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _threads.isEmpty
            ? 3
            : 1 + 1 + _threads.length + (_loading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) return _buildChips();
          if (index == 1) return _buildFeedHeader();
          final threadIndex = index - 2;
          if (_threads.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  const FaIcon(FontAwesomeIcons.comments,
                      color: EnclavdColors.textSecondary, size: 28),
                  const SizedBox(height: 10),
                  const Text(
                    'No posts yet',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: EnclavdColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedId == null
                        ? 'Posts promoted to a domain will show up here.'
                        : 'Nothing has been promoted to this domain yet.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: EnclavdColors.textSecondary),
                  ),
                ],
              ),
            );
          }
          if (threadIndex >= _threads.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: ShimmerBox(width: 160, height: 22)),
            );
          }
          final thread = _threads[threadIndex];
          return DomainThreadRow(
            key: ValueKey(thread.post.id),
            thread: thread,
            social: widget.social,
            onTap: () => _open(thread),
          );
        },
      ),
    );
  }

  Widget _buildChips() {
    if (!_chipsLoaded) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ChipSkeleton(),
            _ChipSkeleton(),
            _ChipSkeleton(),
            _ChipSkeleton(),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _DomainChip(
            label: 'All',
            icon: FontAwesomeIcons.tableCellsLarge,
            iconColor: EnclavdColors.link,
            selected: _selectedId == null,
            onTap: () => _select(null),
          ),
          for (final cat in _categories)
            _DomainChip(
              label: cat.name,
              icon: domainIconFor(cat.icon, codePoint: cat.iconCode),
              iconColor: domainColorFromHex(cat.color),
              selected: _selectedId == cat.id,
              onTap: () => _select(cat.id),
            ),
        ],
      ),
    );
  }

  Widget _buildFeedHeader() {
    DomainCategory? selected;
    for (final c in _categories) {
      if (c.id == _selectedId) {
        selected = c;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
      child: Row(
        children: [
          Text(
            selected != null ? 'Posts in ${selected.name}' : 'Latest Posts',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: EnclavdColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            '$_total total',
            style: const TextStyle(
                fontSize: 11, color: EnclavdColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DomainChip extends StatelessWidget {
  const _DomainChip({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final FaIconData icon;
  final Color iconColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? EnclavdColors.link.withValues(alpha: 0.16)
        : EnclavdColors.cardSecondary;
    final fg = selected ? EnclavdColors.link : EnclavdColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? EnclavdColors.link.withValues(alpha: 0.5)
                : EnclavdColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, size: 11, color: selected ? fg : iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipsSkeleton extends StatelessWidget {
  const _ChipsSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ChipSkeleton(),
          _ChipSkeleton(),
          _ChipSkeleton(),
          _ChipSkeleton(),
        ],
      ),
    );
  }
}

class _ChipSkeleton extends StatelessWidget {
  const _ChipSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ShimmerBox(width: 86, height: 30, borderRadius: 8);
  }
}

class _FeedHeaderSkeleton extends StatelessWidget {
  const _FeedHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: ShimmerBox(width: 130, height: 13),
    );
  }
}
