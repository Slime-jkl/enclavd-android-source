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

/// The site's user-menu dropdown (header.php) as a side menu. Triggered
/// by the avatar in the header (opposite the logo).
///
/// Items (site parity): the current user's avatar/username → their
/// profile; Control Panel (admins only, site-gated); Test Results;
/// Profile; Invitations; Settings; Legal; Report an issue; Sign out.
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
        borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
      ),
      child: SafeArea(
        child: FutureBuilder<CurrentUser?>(
          future: _me,
          builder: (context, snapshot) {
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
                const Divider(height: 1, color: EnclavdColors.divider),
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
                  icon: FontAwesomeIcons.user,
                  iconColor: EnclavdColors.link,
                  label: 'Profile',
                  onTap: user == null
                      ? null
                      : () => _push(ProfileScreen(userId: user.id)),
                ),
                _MenuItem(
                  icon: FontAwesomeIcons.ticket,
                  iconColor: EnclavdColors.link,
                  label: 'Invitations',
                  onTap: () => _openSite('/invitations'),
                ),
                _MenuItem(
                  icon: FontAwesomeIcons.gear,
                  iconColor: const Color(0xFFC084FC), // purple-400 (site)
                  label: 'Settings',
                  onTap: () => _push(const SettingsScreen()),
                ),
                _MenuItem(
                  icon: FontAwesomeIcons.scaleBalanced,
                  iconColor: const Color(0xFFC084FC), // purple-400
                  label: 'Legal',
                  onTap: () => _push(const LegalScreen()),
                ),
                _MenuItem(
                  icon: FontAwesomeIcons.flag,
                  iconColor: const Color(0xFFF87171), // red-400 (site)
                  label: 'Report an issue',
                  onTap: () => _openSite('/reports'),
                ),
                const Divider(height: 1, color: EnclavdColors.divider),
                _MenuItem(
                  icon: FontAwesomeIcons.arrowRightFromBracket,
                  iconColor: EnclavdColors.link,
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

class _UserHeader extends StatelessWidget {
  const _UserHeader({required this.user, required this.onTap});

  final CurrentUser? user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Local copy so the null check promotes (public fields don't).
    final u = user;
    if (u == null) {
      // Session probe in flight or dead — keep the menu usable.
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            ShimmerAvatar(),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enclavd',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  SizedBox(height: 2),
                  Text('…',
                      style: TextStyle(
                          color: EnclavdColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
            FaIcon(FontAwesomeIcons.chevronRight,
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            EnclavdAvatar(
              size: 44,
              url: u.avatarUrl(AppConfig.apiBaseUrl),
              borderColor: personality,
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
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  RankBadge(rank: u.rank),
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

class ShimmerAvatar extends StatelessWidget {
  const ShimmerAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: EnclavdColors.cardSecondary,
      ),
    );
  }
}

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
      leading: FaIcon(icon, size: 17, color: iconColor),
      title: Text(label,
          style: const TextStyle(fontSize: 14, color: EnclavdColors.textPrimary)),
      trailing: onTap == null
          ? null
          : const FaIcon(FontAwesomeIcons.chevronRight,
              size: 12, color: EnclavdColors.textSecondary),
      onTap: onTap,
    );
  }
}
