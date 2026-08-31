import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/domains_service.dart';
import '../api/social_service.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/error_view.dart';
import '../utils/domain_icons.dart';
import '../widgets/domain_thread_row.dart';
import '../widgets/shimmer.dart';
import 'domain_thread_screen.dart';
import '../services/analytics_service.dart';

class DomainCategoryScreen extends StatefulWidget {
  const DomainCategoryScreen({
    super.key,
    required this.domains,
    required this.category,
    this.social,
    this.threadBuilder,
  });

  final DomainsService domains;
  final DomainCategory category;
  final SocialService? social;

  /// Test seam: replaces the pushed thread screen.
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
        // The API's category row is the header source of truth; the
        // navigated name is the fallback when the row is empty.
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
              social: widget.social,
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
          DomainThreadRowSkeleton(),
          DomainThreadRowSkeleton(),
          DomainThreadRowSkeleton(),
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
}

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
            child: FaIcon(
                domainIconFor(category.icon, codePoint: category.iconCode),
                size: 19,
                color: accent),
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
