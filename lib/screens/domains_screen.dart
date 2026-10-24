import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/domains_service.dart';
import '../api/social_service.dart';
import '../theme/enclavd_theme.dart';
import '../utils/domain_icons.dart';
import '../widgets/domain_thread_row.dart';
import '../widgets/shimmer.dart';
import 'domain_thread_screen.dart';

/// The Domains tab home: the root categories as filter buttons with a
/// latest-posts feed below (newest activity first). A category's domains
/// stay collapsed until it is picked, then they appear in their own row;
/// "All" shows every domain's posts.
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
  List<DomainCategory> _roots = const [];
  Map<int, DomainCategory> _index = const {};
  Map<int, List<DomainCategory>> _children = const {};
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
      final index = <int, DomainCategory>{for (final c in flat) c.id: c};
      final children = <int, List<DomainCategory>>{};
      final roots = <DomainCategory>[];
      for (final c in flat) {
        final parent = c.parent;
        if (parent != null && index.containsKey(parent)) {
          children.putIfAbsent(parent, () => []).add(c);
        } else {
          roots.add(c);
        }
      }
      if (!mounted) return;
      setState(() {
        _index = index;
        _children = children;
        _roots = roots;
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

  /// Selected domain and its ancestors, root first.
  List<DomainCategory> _pathOf(int? id) {
    final chain = <DomainCategory>[];
    var node = id == null ? null : _index[id];
    while (node != null && chain.length < 8) {
      chain.insert(0, node);
      node = _index[node.parent];
    }
    return chain;
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
    if (!_chipsLoaded) {
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
    // Chips stay mounted while the feed reloads, so drilling down never
    // blanks the row you just opened.
    final showEmpty = _initialLoadDone && _threads.isEmpty && _error == null;
    final showError = _initialLoadDone && _threads.isEmpty && _error != null;
    final showSkeleton = _threads.isEmpty && !showEmpty && !showError;
    return RefreshIndicator(
      onRefresh: () => _loadFeed(reset: true),
      color: context.enclavd.link,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: 2 +
            (showEmpty || showError || showSkeleton
                ? 1
                : _threads.length + (_loading ? 1 : 0)),
        itemBuilder: (context, index) {
          if (index == 0) return _buildChips();
          if (index == 1) return _buildFeedHeader();
          if (showError) return _buildFeedError();
          if (showEmpty) return _buildEmpty();
          if (showSkeleton) return _buildRowsSkeleton();
          final threadIndex = index - 2;
          if (threadIndex >= _threads.length) return _buildLoadingRow();
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

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          FaIcon(FontAwesomeIcons.comments,
              color: context.enclavd.textSecondary, size: 28),
          const SizedBox(height: 10),
          Text(
            'No posts yet',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.enclavd.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedId == null
                ? 'Posts promoted to a domain will show up here.'
                : 'Nothing has been promoted to this domain yet.',
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 12.5, color: context.enclavd.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedError() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        children: [
          FaIcon(FontAwesomeIcons.cloudArrowDown,
              size: 32, color: context.enclavd.textSecondary),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: context.enclavd.textSecondary),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => _loadFeed(reset: true),
            style: TextButton.styleFrom(
              foregroundColor: context.enclavd.link,
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _buildRowsSkeleton() {
    return const Column(
      children: [
        DomainThreadRowSkeleton(),
        DomainThreadRowSkeleton(),
        DomainThreadRowSkeleton(),
      ],
    );
  }

  Widget _buildLoadingRow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(child: ShimmerBox(width: 160, height: 22)),
    );
  }

  /// Root categories only. Whatever is selected unfolds one row per level
  /// below it, so a subdomain is never listed before its category is picked.
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
    final path = _pathOf(_selectedId);
    final inPath = <int>{
      for (final node in path)
        if (node.id != _selectedId) node.id,
    };
    final rows = <Widget>[
      _chipRow([
        _DomainChip(
          label: 'All',
          icon: FontAwesomeIcons.tableCellsLarge,
          iconColor: context.enclavd.link,
          selected: _selectedId == null,
          onTap: () => _select(null),
        ),
        for (final root in _roots) _chipFor(root, inPath: inPath),
      ]),
    ];
    for (final node in path) {
      final children = _children[node.id];
      if (children == null || children.isEmpty) continue;
      rows.add(_chipRow([
        _DomainChip(
          label: 'Everything',
          icon: domainIconFor(node.icon, codePoint: node.iconCode),
          iconColor:
              context.enclavd.accentGlyph(domainColorFromHex(node.color)),
          selected: _selectedId == node.id,
          onTap: () => _select(node.id),
        ),
        for (final child in children) _chipFor(child),
      ]));
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(children: rows),
      ),
    );
  }

  Widget _chipRow(List<Widget> chips) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Wrap(spacing: 8, runSpacing: 8, children: chips),
      );

  Widget _chipFor(DomainCategory cat, {Set<int> inPath = const {}}) =>
      _DomainChip(
        label: cat.name,
        icon: domainIconFor(cat.icon, codePoint: cat.iconCode),
        iconColor: context.enclavd.accentGlyph(domainColorFromHex(cat.color)),
        selected: _selectedId == cat.id,
        inPath: inPath.contains(cat.id),
        onTap: () => _select(cat.id),
      );

  Widget _buildFeedHeader() {
    final selected = _selectedId == null ? null : _index[_selectedId];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
      child: Row(
        children: [
          Text(
            selected != null ? 'Posts in ${selected.name}' : 'Latest Posts',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: context.enclavd.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            '$_total total',
            style:
                TextStyle(fontSize: 11, color: context.enclavd.textSecondary),
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
    this.inPath = false,
  });

  final String label;
  final FaIconData icon;
  final Color iconColor;
  final bool selected;

  /// Ancestor of the current selection: tinted label, no fill.
  final bool inPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? context.enclavd.link.withValues(alpha: 0.14)
        : context.enclavd.cardSecondary;
    final fg = selected || inPath
        ? context.enclavd.link
        : context.enclavd.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
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
