import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../api/profile_service.dart';
import '../screens/profile_screen.dart';
import '../theme/enclavd_theme.dart';

/// The site profile.php invitation block: "Invited by" (the inviter link,
/// [System] or Unknown) plus "Invited members" - the first 8 links, with
/// the full list behind "See full list (N)".
class InvitationInfo extends StatelessWidget {
  const InvitationInfo({
    super.key,
    required this.invitedById,
    required this.invitedByUsername,
    required this.members,
    this.onOpenProfile,
  });

  final int invitedById;
  final String invitedByUsername;
  final List<InvitedMember> members;

  /// Test seam: replaces the pushed profile screen.
  final void Function(int userId)? onOpenProfile;

  static const int previewCount = 8;

  void _openProfile(BuildContext context, int userId) {
    final open = onOpenProfile;
    if (open != null) {
      open(userId);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProfileScreen(userId: userId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final secondary = context.enclavd.textSecondary;
    final shown = members.take(previewCount).toList();
    final hidden = members.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FaIcon(FontAwesomeIcons.envelopeOpenText,
                size: 13, color: secondary),
            const SizedBox(width: 6),
            Text('Invited by',
                style: TextStyle(color: secondary, fontSize: 13)),
            const SizedBox(width: 8),
            if (invitedById <= 0)
              Text('[System]', style: TextStyle(color: secondary, fontSize: 13))
            else if (invitedByUsername.isEmpty)
              Text('Unknown', style: TextStyle(color: secondary, fontSize: 13))
            else
              Flexible(
                child: _MemberLink(
                  label: '$invitedByUsername#$invitedById',
                  color: context.enclavd.link,
                  onTap: () => _openProfile(context, invitedById),
                ),
              ),
          ],
        ),
        if (members.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              FaIcon(FontAwesomeIcons.envelopeCircleCheck,
                  size: 13, color: secondary),
              const SizedBox(width: 6),
              Text('Invited members',
                  style: TextStyle(color: secondary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final member in shown)
                _MemberLink(
                  label: '${member.username}#${member.id}',
                  color: _memberColor(context, member),
                  lineThrough: member.isBlocked,
                  onTap: () => _openProfile(context, member.id),
                ),
              if (hidden > 0)
                _MemberLink(
                  label: 'See full list (${members.length})',
                  color: context.enclavd.link,
                  onTap: () => _openAll(context),
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _openAll(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.enclavd.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => InvitedMembersSheet(
        members: members,
        onOpenProfile: (id) {
          Navigator.of(context).pop();
          _openProfile(context, id);
        },
      ),
    );
  }
}

/// The site's invited-members modal as a bottom sheet (full list).
class InvitedMembersSheet extends StatelessWidget {
  const InvitedMembersSheet({
    super.key,
    required this.members,
    required this.onOpenProfile,
  });

  final List<InvitedMember> members;
  final void Function(int userId) onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Text('Invited members',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: context.enclavd.textPrimary)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: FaIcon(FontAwesomeIcons.xmark,
                      size: 18, color: context.enclavd.textSecondary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.enclavd.divider),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: members.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: context.enclavd.divider),
              itemBuilder: (context, index) {
                final member = members[index];
                final color = _memberColor(context, member);
                return InkWell(
                  onTap: () => onOpenProfile(member.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${member.username}#${member.id}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              decoration: member.isBlocked
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: color,
                            ),
                          ),
                        ),
                        FaIcon(FontAwesomeIcons.chevronRight,
                            size: 12, color: context.enclavd.textSecondary),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Site's getRankStyles(rank, is_active): blocked members read as Barred.
Color _memberColor(BuildContext context, InvitedMember member) =>
    member.isBlocked
        ? context.enclavd.rankName('Blocked')
        : context.enclavd.rankName(member.rank);

class _MemberLink extends StatelessWidget {
  const _MemberLink({
    required this.label,
    required this.color,
    required this.onTap,
    this.lineThrough = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool lineThrough;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          decoration: lineThrough ? TextDecoration.lineThrough : null,
          decorationColor: color,
        ),
      ),
    );
  }
}
