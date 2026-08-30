import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/auth_service.dart'; // resolveMediaUrl
import '../api/domains_service.dart';
import '../api/social_service.dart';
import '../config/app_config.dart';
import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';
import '../utils/db_time.dart';
import '../utils/domain_icons.dart';
import 'enclavd_avatar.dart';
import 'shimmer.dart'; // ShimmerBox


class DomainThreadRow extends StatefulWidget {
  const DomainThreadRow({
    super.key,
    required this.thread,
    required this.onTap,
    this.social,
  });

  final DomainThread thread;
  final VoidCallback onTap;
  final SocialService? social;

  @override
  State<DomainThreadRow> createState() => _DomainThreadRowState();
}

class _DomainThreadRowState extends State<DomainThreadRow> {
  late int _likeCount;
  late bool _liked;
  bool _likeBusy = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.thread.post.likeCount;
    _liked = widget.thread.post.userLiked;
  }

  Future<void> _toggleLike() async {
    final social = widget.social;
    if (social == null || _likeBusy) return;
    setState(() {
      _likeBusy = true;
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    if (_liked) SoundService.instance.like();
    try {
      final result = await social.toggleLike(widget.thread.post.id);
      if (!mounted) return;
      setState(() {
        _liked = result.liked;
        _likeCount = result.likeCount;
        _likeBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = !_liked;
        _likeCount += _liked ? 1 : -1;
        _likeBusy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final post = thread.post;
    final accent = domainColorFromHex(thread.domainColor);
    final (title, body) = _splitContent(post.content);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: EnclavdColors.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Meta: avatar + username + time | domain badge.
                Row(
                  children: [
                    EnclavdAvatar(
                      size: 24,
                      url: resolveMediaUrl(AppConfig.apiBaseUrl,
                          avatarPath: post.profilePictureUrl),
                      borderColor: PersonalityColors.forType(post.personalityType),
                      square: true,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
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
                    Text('- ${relativeTime(post.createdAt)}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: EnclavdColors.textSecondary)),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: _DomainBadge(thread: thread, accent: accent),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    color: EnclavdColors.textPrimary,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: EnclavdColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Divider(height: 1, color: EnclavdColors.border),
                const SizedBox(height: 8),
                // Footer: like + replies | last reply.
                Row(
                  children: [
                    _LikeButton(
                      liked: _liked,
                      count: _likeCount,
                      busy: _likeBusy,
                      onTap: _toggleLike,
                    ),
                    const SizedBox(width: 18),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FaIcon(FontAwesomeIcons.comment,
                            size: 14, color: EnclavdColors.textSecondary),
                        const SizedBox(width: 5),
                        Text(
                          '${post.commentCount}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: EnclavdColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (thread.lastReplyAt != null &&
                        thread.lastReplyUsername != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: _lastReply(thread),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _lastReply(DomainThread thread) {
    final blocked = thread.lastReplyActive == 'false';
    return Text.rich(
      TextSpan(
        style: const TextStyle(
            fontSize: 11, color: EnclavdColors.textSecondary),
        children: [
          TextSpan(
              text: 'Last reply ${relativeTime(thread.lastReplyAt!)} @'),
          TextSpan(
            text: thread.lastReplyUsername!,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: blocked
                  ? RankColors.forRank('Blocked')
                  : RankColors.forRank(thread.lastReplyRank ?? 'Member'),
            ),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.liked,
    required this.count,
    required this.busy,
    required this.onTap,
  });

  final bool liked;
  final int count;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        liked ? EnclavdColors.likeActive : EnclavdColors.textSecondary;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(FontAwesomeIcons.heart, size: 15, color: color),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DomainBadge extends StatelessWidget {
  const _DomainBadge({required this.thread, required this.accent});

  final DomainThread thread;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: EnclavdColors.cardSecondary,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: EnclavdColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            domainIconFor(thread.domainIcon),
            size: 10,
            color: accent,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              thread.domainName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: EnclavdColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

(String, String) _splitContent(String content) {
  final normalized =
      content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (normalized.isEmpty) return ('(no content)', '');
  final lines = normalized.split('\n');
  var title = lines.first.trim();
  if (title.isEmpty && lines.length > 1) {
    title = lines.skip(1).join('\n').trim();
    return (title, '');
  }
  final body = lines.skip(1).join('\n').trim();
  return (title, body);
}

/// Loading placeholder for DomainThreadRow
class DomainThreadRowSkeleton extends StatelessWidget {
  const DomainThreadRowSkeleton({super.key});

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShimmerBox(width: 24, height: 24, borderRadius: 7),
                  SizedBox(width: 8),
                  ShimmerBox(width: 110, height: 12),
                  Spacer(),
                  ShimmerBox(width: 70, height: 18, borderRadius: 7),
                ],
              ),
              SizedBox(height: 10),
              ShimmerBox(width: double.infinity, height: 13),
              SizedBox(height: 6),
              ShimmerBox(width: 190, height: 13),
              SizedBox(height: 10),
              Divider(height: 1, color: EnclavdColors.border),
              SizedBox(height: 10),
              Row(
                children: [
                  ShimmerBox(width: 42, height: 14),
                  SizedBox(width: 18),
                  ShimmerBox(width: 42, height: 14),
                  Spacer(),
                  ShimmerBox(width: 110, height: 11),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
