import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/domains_service.dart';
import '../api/messages_service.dart'; // parseDbTime (DB UTC wall-clock)
import '../theme/enclavd_theme.dart';
import '../utils/domain_icons.dart';
import '../widgets/shimmer.dart';
import 'domain_category_screen.dart';

/// The native Domains tab — the site's /domain board as a modern app.
///
/// Domains are a STRUCTURED way to navigate content (forum-style, unlike
/// the ranked feed): root categories each hold subcategories, and every
/// category leads to its threads. The board lists the root categories as
/// cards with their children, post counts and latest activity; tapping a
/// category opens its thread list.
///
/// This widget is the FEED SHELL's Domains tab body (no Scaffold/AppBar of
/// its own — the shell supplies the shared header and bottom nav), built
/// lazily on first tab visit like the Updates tab.
class DomainsScreen extends StatefulWidget {
  const DomainsScreen({super.key, required this.domains, this.categoryBuilder});

  final DomainsService domains;

  /// Test seam — replaces the pushed category screen so widget tests never
  /// touch the network.
  final Widget Function(DomainCategory category)? categoryBuilder;

  @override
  State<DomainsScreen> createState() => _DomainsScreenState();
}

class _DomainsScreenState extends State<DomainsScreen> {
  List<DomainCategory> _roots = const [];
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
      final flat = await widget.domains.board();
      if (!mounted) return;
      setState(() {
        _roots = DomainCategory.buildTree(flat);
        _loading = false;
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load domains.';
        _loading = false;
      });
    }
  }

  void _open(DomainCategory category) {
    final builder = widget.categoryBuilder;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => builder != null
          ? builder(category)
          : DomainCategoryScreen(
              domains: widget.domains,
              category: category,
            ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    if (!_loaded && _loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _BoardHeaderSkeleton(),
          _CategoryCardSkeleton(),
          _CategoryCardSkeleton(),
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
    if (_roots.isEmpty) {
      // Site empty state (domain/index.php board: "No domains have been
      // created yet.").
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(FontAwesomeIcons.sitemap,
                color: EnclavdColors.textSecondary, size: 28),
            SizedBox(height: 10),
            Text('No domains yet',
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
          // Board header: the site's "Domains of Discussion" title block.
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Text(
              'Domains of Discussion',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: EnclavdColors.textPrimary,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(
              'Browse discussions by category',
              style: TextStyle(
                  fontSize: 13, color: EnclavdColors.textSecondary),
            ),
          ),
          for (final root in _roots)
            _CategoryCard(
              root: root,
              onOpen: _open,
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// One root category card: the root's header (icon chip + name + count)
/// with its subcategories as rows below (site board view: root header over
/// child rows). Tapping the root OR any child opens that category.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.root, required this.onOpen});

  final DomainCategory root;
  final void Function(DomainCategory) onOpen;

  @override
  Widget build(BuildContext context) {
    final accent = domainColorFromHex(root.color);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Root header (site: bg-gray-900/60 header over the rows).
            InkWell(
              onTap: () => onOpen(root),
              child: Container(
                width: double.infinity,
                color: EnclavdColors.background.withValues(alpha: 0.45),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    _IconChip(icon: domainIconFor(root.icon), color: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            root.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: EnclavdColors.textPrimary,
                            ),
                          ),
                          if (root.description != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              root.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: EnclavdColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _PostCount(count: root.postCount),
                    const SizedBox(width: 4),
                    const FaIcon(FontAwesomeIcons.chevronRight,
                        size: 12, color: EnclavdColors.textSecondary),
                  ],
                ),
              ),
            ),
            if (root.children.isNotEmpty)
              for (final child in root.children)
                _ChildRow(
                  category: child,
                  onTap: () => onOpen(child),
                )
            else
              // A root with no subcategories: the header IS the row; the
              // last-activity line sits under it (the site's "General
              // Discussion" row with its last-post block).
              _ActivityLine(category: root),
          ],
        ),
      ),
    );
  }
}

/// The root's latest-activity line, shown under a childless root's header
/// (site: "Last: <date> by @author" or "No activity").
class _ActivityLine extends StatelessWidget {
  const _ActivityLine({required this.category});

  final DomainCategory category;

  @override
  Widget build(BuildContext context) {
    final last = category.lastPostAt;
    final author = category.lastPostAuthor;
    final hasActivity = last != null && author != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: hasActivity
          ? Text.rich(
              TextSpan(
                style: const TextStyle(
                    fontSize: 11, color: EnclavdColors.textSecondary),
                children: [
                  const TextSpan(text: 'Last: '),
                  TextSpan(
                      text: _formatDate(last),
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: ' by @$author'),
                ],
              ),
            )
          : const Text(
              'No activity yet',
              style: TextStyle(
                  fontSize: 11, color: EnclavdColors.textSecondary),
            ),
    );
  }
}

/// A subcategory row inside a root card (site board: child rows with icon,
/// name, post count and latest activity).
class _ChildRow extends StatelessWidget {
  const _ChildRow({required this.category, required this.onTap});

  final DomainCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = domainColorFromHex(category.color);
    final last = category.lastPostAt;
    final author = category.lastPostAuthor;
    final hasActivity = last != null && author != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const SizedBox(width: 18), // indent under the root header
            _IconChip(icon: domainIconFor(category.icon), color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: EnclavdColors.textPrimary,
                    ),
                  ),
                  if (category.description != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      category.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5,
                          color: EnclavdColors.textSecondary),
                    ),
                  ],
                  if (hasActivity) ...[
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                            fontSize: 11,
                            color: EnclavdColors.textSecondary),
                        children: [
                          const TextSpan(text: 'Last: '),
                          TextSpan(
                              text: _formatDate(last),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          TextSpan(text: ' by @$author'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _PostCount(count: category.postCount),
            const SizedBox(width: 4),
            const FaIcon(FontAwesomeIcons.chevronRight,
                size: 12, color: EnclavdColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Rounded icon chip: tinted square with the category's accent color at
/// ~13% alpha (the drawer's icon-chip pattern), colored icon inside.
class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.color});

  final FaIconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: FaIcon(icon, size: 15, color: color),
    );
  }
}

/// The site's post-count block: bold number over a tiny "Posts" label.
class _PostCount extends StatelessWidget {
  const _PostCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: EnclavdColors.textPrimary,
          ),
        ),
        const Text(
          'posts',
          style: TextStyle(fontSize: 10, color: EnclavdColors.textSecondary),
        ),
      ],
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

/// First-load skeleton: a title block + two category card shapes.
class _BoardHeaderSkeleton extends StatelessWidget {
  const _BoardHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(width: 210, height: 20),
          SizedBox(height: 8),
          ShimmerBox(width: 160, height: 13),
        ],
      ),
    );
  }
}

/// Skeleton of a category card (root header + a couple of child lines).
class _CategoryCardSkeleton extends StatelessWidget {
  const _CategoryCardSkeleton();

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
            Padding(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  ShimmerBox(width: 34, height: 34, borderRadius: 9),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(width: 120, height: 14),
                        SizedBox(height: 6),
                        ShimmerBox(width: 180, height: 11),
                      ],
                    ),
                  ),
                  ShimmerBox(width: 30, height: 24),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Row(
                children: [
                  SizedBox(width: 18),
                  ShimmerBox(width: 26, height: 26, borderRadius: 7),
                  SizedBox(width: 12),
                  ShimmerBox(width: 140, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
