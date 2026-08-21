import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/auth_service.dart';
import '../config/app_config.dart';
import '../screens/legal_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/settings_screen.dart';
import '../theme/enclavd_theme.dart';
import 'enclavd_avatar.dart';
import 'rank_badge.dart';
import 'shimmer.dart';

/// The user menu as a modern app drawer (NOT site-accurate — the site's
/// dropdown is a flat Tailwind list; this is a native-style drawer).
/// Triggered by the avatar in the header.
///
/// While the session probe ([AuthService.me]) is in flight the WHOLE menu
/// shows a shimmer skeleton; once loaded it renders a grouped layout:
/// identity header (personality-tinted gradient, rank-colored username,
/// rank badge + personality chip) then icon-chip menu items under
/// uppercase section labels (Account / Community / Support), sign out
/// separated at the bottom.
///
/// Items (functionality parity with the site menu): the current user's
/// avatar/username → their profile; Control Panel (admins only);
/// Test Results; Profile; Invitations; Settings; Legal; Report an issue;
/// Sign out.
class UserMenuDrawer extends StatefulWidget {
  const UserMenuDrawer({
    super.key,
    required this.auth,
    required this.onSignOut,
  });

  final AuthService auth;

  /// Wired by the owning screen: logs out via api/v1 and returns to the
  /// login screen (the site's /logout).
  final VoidCallback onSignOut;

  @override
  State<UserMenuDrawer> createState() => _UserMenuDrawerState();
}

class _UserMenuDrawerState extends State<UserMenuDrawer> {
  Future<CurrentUser?>? _me;

  @override
  void initState() {
    super.initState();
    _me = widget.auth.me();
  }

  void _openSite(String path) {
    // The site's menu links open pages in the same tab; the app hands
    // them to the browser.
    launchUrl(
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
      mode: LaunchMode.externalApplication,
    );
  }

  void _push(Widget screen) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: EnclavdColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
      ),
      child: SafeArea(
        child: FutureBuilder<CurrentUser?>(
          future: _me,
          builder: (context, snapshot) {
            // Loading = the menu's own skeleton (header block + menu
            // rows) under the shared Shimmer, so the drawer never shows
            // a bare layout or a static placeholder.
            if (snapshot.connectionState != ConnectionState.done) {
              return const _MenuSkeleton();
            }
            final user = snapshot.data;
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                _UserHeader(
                  user: user,
                  onTap: user == null
                      ? null
                      : () => _push(ProfileScreen(userId: user.id)),
                ),
                const _SectionLabel('Account'),
                _MenuItem(
                  icon: FontAwesomeIcons.user,
                  iconColor: EnclavdColors.link,
                  label: 'Profile',
                  onTap: user == null
                      ? null
                      : () => _push(ProfileScreen(userId: user.id)),
                ),
                _MenuItem(
                  icon: FontAwesomeIcons.gear,
                  iconColor: const Color(0xFFC084FC), // purple-400
                  label: 'Settings',
                  onTap: () => _push(const SettingsScreen()),
                ),
                const _SectionLabel('Community'),
                if (user?.isAdmin ?? false)
                  _MenuItem(
                    icon: FontAwesomeIcons.shieldHalved,
                    iconColor: const Color(0xFFC084FC), // purple-400
                    label: 'Control Panel',
                    onTap: () => _openSite('/admin'),
                  ),
                _MenuItem(
                  icon: FontAwesomeIcons.chartPie,
                  iconColor: EnclavdColors.link,
                  label: 'Test Results',
                  onTap: () => _openSite('/results'),
                ),
                _MenuItem(
                  icon: FontAwesomeIcons.ticket,
                  iconColor: const Color(0xFFFACC15), // yellow-400
                  label: 'Invitations',
                  onTap: () => _openSite('/invitations'),
                ),
                const _SectionLabel('Support'),
                _MenuItem(
                  icon: FontAwesomeIcons.scaleBalanced,
                  iconColor: const Color(0xFF60A5FA), // blue-400
                  label: 'Legal',
                  onTap: () => _push(const LegalScreen()),
                ),
                _MenuItem(
                  icon: FontAwesomeIcons.flag,
                  iconColor: const Color(0xFFF87171), // red-400
                  label: 'Report an issue',
                  onTap: () => _openSite('/reports'),
                ),
                const Divider(
                  height: 24,
                  indent: 16,
                  endIndent: 16,
                  color: EnclavdColors.divider,
                ),
                _MenuItem(
                  icon: FontAwesomeIcons.arrowRightFromBracket,
                  iconColor: EnclavdColors.likeActive,
                  label: 'Sign out',
                  onTap: widget.onSignOut,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Uppercase section label between menu groups (the modern-drawer look:
/// spacing + labels instead of the site's full-width dividers).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
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

class _UserHeader extends StatelessWidget {
  const _UserHeader({required this.user, required this.onTap});

  final CurrentUser? user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Local copy so the null check promotes (public fields don't).
    final u = user;
    if (u == null) {
      // Session probe finished without a user (dead/absent session) —
      // keep the menu usable with a neutral identity header.
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: EnclavdColors.cardSecondary,
              ),
              child: const FaIcon(FontAwesomeIcons.user,
                  size: 18, color: EnclavdColors.textSecondary),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enclavd',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Session unavailable',
                    style: TextStyle(
                        color: EnclavdColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const FaIcon(FontAwesomeIcons.chevronRight,
                size: 14, color: EnclavdColors.textSecondary),
          ],
        ),
      );
    }
    final personality = PersonalityColors.forType(u.personalityType);
    final rankColor = u.rank == 'Blocked'
        ? RankColors.forRank('Blocked')
        : RankColors.forRank(u.rank);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          // A subtle personality-tinted gradient — the header reads as an
          // identity card, not a list row.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              (personality ?? EnclavdColors.cardSecondary)
                  .withValues(alpha: 0.28),
              EnclavdColors.card,
            ],
          ),
        ),
        child: Row(
          children: [
            EnclavdAvatar(
              size: 46,
              url: u.avatarUrl(AppConfig.apiBaseUrl),
              borderColor: personality ?? EnclavdColors.border,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u.username,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: rankColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      RankBadge(rank: u.rank),
                      if (u.personalityType != null) ...[
                        const SizedBox(width: 6),
                        _PersonalityChip(type: u.personalityType!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const FaIcon(FontAwesomeIcons.chevronRight,
                size: 14, color: EnclavdColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Small pill with the MBTI type, tinted by its personality group color —
/// the native counterpart of the site's personality badge.
class _PersonalityChip extends StatelessWidget {
  const _PersonalityChip({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final color = PersonalityColors.forType(type) ?? EnclavdColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }
}

/// Menu row with an icon CHIP (tinted rounded square) instead of a bare
/// glyph — the modern-drawer item shape. Trailing chevron only when the
/// row is tappable.
class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final FaIconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(10),
        ),
        child: FaIcon(icon, size: 15, color: iconColor),
      ),
      title: Text(label,
          style: const TextStyle(
              fontSize: 14, color: EnclavdColors.textPrimary)),
      trailing: onTap == null
          ? null
          : const FaIcon(FontAwesomeIcons.chevronRight,
              size: 12, color: EnclavdColors.textSecondary),
      onTap: onTap,
    );
  }
}

/// The drawer's loading state: a skeleton of the real layout (identity
/// header + section labels + menu rows) under the shared [Shimmer], so
/// the menu visibly loads instead of flashing a bare list.
class _MenuSkeleton extends StatelessWidget {
  const _MenuSkeleton();

  @override
  Widget build(BuildContext context) {
    const row = Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      child: Row(
        children: [
          ShimmerBox(width: 34, height: 34, borderRadius: 10),
          SizedBox(width: 12),
          ShimmerBox(width: 130, height: 13),
        ],
      ),
    );
    return ListView(
      padding: EdgeInsets.zero,
      children: const [
        // Identity header block.
        Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              ShimmerBox(width: 46, height: 46, shape: BoxShape.circle),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(width: 110, height: 15),
                  SizedBox(height: 8),
                  ShimmerBox(width: 70, height: 12),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: ShimmerBox(width: 60, height: 10),
        ),
        row,
        row,
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: ShimmerBox(width: 76, height: 10),
        ),
        row,
        row,
        row,
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: ShimmerBox(width: 56, height: 10),
        ),
        row,
        row,
      ],
    );
  }
}
