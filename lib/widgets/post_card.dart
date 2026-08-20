import 'package:flutter/material.dart';

import '../api/auth_service.dart';
import '../api/feed_service.dart';
import '../theme/enclavd_theme.dart';

/// Post card — visual port of feed/components/post_card.php.
///
/// Layout (top→bottom):
///   avatar (35px, personality-colored border) · username (rank color)
///   · personality badge · warning count ⚠ · relative time (right)
///   content (pre-line, clamped, "Show more")
///   image (when present; /public/gallery/<name>)
///   like ♥ count · comment count (bottom row)
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.apiBaseUrl,
  });

  final Post post;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AuthorRow(post: post, apiBaseUrl: apiBaseUrl),
            const SizedBox(height: 8),
            _PostContent(post: post),
            if (post.image != null && post.image!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _PostImage(post: post, apiBaseUrl: apiBaseUrl),
            ],
            const Divider(height: 24),
            _ActionRow(post: post),
          ],
        ),
      ),
    );
  }
}

/// Author row: avatar + username + badges + relative time.
class _AuthorRow extends StatelessWidget {
  const _AuthorRow({required this.post, required this.apiBaseUrl});

  final Post post;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final personality = PersonalityColors.forType(post.personalityType);
    return Row(
      children: [
        // 35px circular avatar, personality-colored border (border_color),
        // falls back to default-avatar on error — matches the site's onerror.
        Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: EnclavdColors.cardSecondary,
            border: Border.all(
              color: personality ?? EnclavdColors.border,
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.network(
            resolveMediaUrl(apiBaseUrl, avatarPath: post.profilePictureUrl),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 18),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      post.username,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: post.isBlocked
                            ? RankColors.forRank('Blocked')
                            : RankColors.forRank(post.rank),
                        fontWeight: FontWeight.w600,
                        decoration: post.isBlocked ? TextDecoration.lineThrough : null,
                        decorationColor: RankColors.forRank('Blocked'),
                      ),
                    ),
                  ),
                  if (post.personalityType != null) ...[
                    const SizedBox(width: 6),
                    // Compact 4-letter badge (render_personality_badge,
                    // compact=true → the type code, colored per archetype).
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: EnclavdColors.cardSecondary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        post.personalityType!.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: personality ?? EnclavdColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                  if (post.warningCount > 0) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.warning_amber_rounded,
                        color: EnclavdColors.warning, size: 14),
                    Text('${post.warningCount}',
                        style: const TextStyle(
                            color: EnclavdColors.warning, fontSize: 10)),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Relative time — format_date() port ('now', '5m', '3h', '2d', '1m', '1y').
        Text(
          relativeTime(post.createdAt),
          style: const TextStyle(color: EnclavdColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

/// Content with the site's show-more heuristic:
/// overflow when >250 chars, or (chars + newlines*75) > 300 → clamp to 4
/// lines + "Show more" button.
class _PostContent extends StatefulWidget {
  const _PostContent({required this.post});

  final Post post;

  @override
  State<_PostContent> createState() => _PostContentState();
}

class _PostContentState extends State<_PostContent> {
  bool _expanded = false;

  bool get _needsOverflow {
    final content = widget.post.content;
    final charCount = content.trim().length;
    final newlineCount = '\n'.allMatches(content).length;
    return charCount > 250 || (charCount + newlineCount * 75) > 300;
  }

  @override
  Widget build(BuildContext context) {
    final needs = _needsOverflow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.post.content,
          maxLines: needs && !_expanded ? 4 : null,
          overflow: needs && !_expanded ? TextOverflow.ellipsis : null,
          style: const TextStyle(
            fontSize: 15,
            height: 1.15,
            color: EnclavdColors.textPrimary,
          ),
        ),
        if (needs)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 4),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_expanded ? 'Show less' : 'Show more'),
          ),
      ],
    );
  }
}

/// Post image: BARE gallery filename → /public/gallery/<name>.
/// Mirrors the site's max-h-[50vh] centered image.
class _PostImage extends StatelessWidget {
  const _PostImage({required this.post, required this.apiBaseUrl});

  final Post post;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
        child: Image.network(
          resolveMediaUrl(apiBaseUrl, galleryName: post.image),
          fit: BoxFit.contain,
          width: double.infinity,
          errorBuilder: (_, __, ___) => Container(
            height: 120,
            color: EnclavdColors.cardSecondary,
            child: const Icon(Icons.broken_image_outlined,
                color: EnclavdColors.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// Like + comment counts (read-only in the first milestone; toggling comes
/// with the CSRF-capable POST layer).
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          post.userLiked ? Icons.favorite : Icons.favorite_border,
          color: post.userLiked ? EnclavdColors.likeActive : EnclavdColors.textSecondary,
          size: 22,
        ),
        const SizedBox(width: 6),
        Text('${post.likeCount}',
            style: const TextStyle(color: EnclavdColors.textSecondary)),
        const SizedBox(width: 28),
        const Icon(Icons.chat_bubble_outline,
            color: EnclavdColors.textSecondary, size: 22),
        const SizedBox(width: 6),
        Text('${post.commentCount}',
            style: const TextStyle(color: EnclavdColors.textSecondary)),
      ],
    );
  }
}

/// Port of feed/render_functions.php format_date():
/// now / Xm / Xh / Xd / Xm(month) / Xy — minutes shown as 'm' like the site.
String relativeTime(String dbDateTime) {
  final parsed = DateTime.tryParse(dbDateTime.replaceFirst(' ', 'T'));
  if (parsed == null) return '';
  final now = DateTime.now();
  final diff = now.difference(parsed);
  if (diff.inSeconds < 0) return 'now';
  if (diff.inMinutes < 1) return 'now';
  if (diff.inHours < 1) return '${diff.inMinutes}m';
  if (diff.inDays < 1) return '${diff.inHours}h';
  // Approximate months as 30 days (matches PHP's DateTime::diff month units).
  final days = diff.inDays;
  if (days < 30) return '${days}d';
  if (days < 365) return '${days ~/ 30}m';
  return '${days ~/ 365}y';
}
