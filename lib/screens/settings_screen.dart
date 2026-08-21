import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../services/message_notifications.dart';
import '../services/social_notifications.dart';
import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';

/// Settings — the app-side equivalent of the site's /profile-edit.
///
/// What the native client can actually control lives here (sound effects),
/// plus an "edit your profile on the website" link for everything the app
/// cannot do (bio, avatar, password…). The sounds preference persists via
/// SharedPreferences and drives SoundService.muted.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const routeName = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _prefsKey = 'sounds_enabled';
  static const _notifPrefsKey = MessageNotifications.enabledPrefsKey;
  static const _socialNotifPrefsKey = SocialNotifications.enabledPrefsKey;

  bool? _soundsEnabled; // null until loaded
  bool? _notificationsEnabled; // null until loaded
  bool? _socialNotificationsEnabled; // null until loaded
  bool? _osBlocked; // null until checked; true = OS denies notifications

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsKey) ?? true;
    SoundService.muted = !enabled;
    final notifications = prefs.getBool(_notifPrefsKey) ?? true;
    final social = prefs.getBool(_socialNotifPrefsKey) ?? true;
    if (!mounted) return;
    setState(() {
      _soundsEnabled = enabled;
      _notificationsEnabled = notifications;
      _socialNotificationsEnabled = social;
    });
    await _refreshOsBlocked();
  }

  /// Mirrors the REAL OS state next to the toggle: Android 13+ can deny
  /// notifications at the system level (denied popup, or blocked in
  /// system settings) and the plugin can never re-prompt — the toggle
  /// would read ON while nothing ever shows. The warning row makes that
  /// visible instead of silently dead. Null instance (tests, pre-feed)
  /// simply means "no information" → not blocked.
  Future<void> _refreshOsBlocked() async {
    final notifications = MessageNotifications.instance;
    var blocked = false;
    if (notifications != null && _notificationsEnabled == true) {
      blocked = !await notifications.osNotificationsEnabled();
    }
    if (!mounted) return;
    setState(() => _osBlocked = blocked);
  }

  Future<void> _toggleSounds(bool enabled) async {
    setState(() => _soundsEnabled = enabled);
    SoundService.muted = !enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, enabled);
  }

  Future<void> _toggleNotifications(bool enabled) async {
    setState(() => _notificationsEnabled = enabled);
    await MessageNotifications.instance?.setEnabled(enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifPrefsKey, enabled);
    // The re-request may have been denied again — re-check the OS state
    // so the warning (if any) reflects reality immediately.
    await _refreshOsBlocked();
  }

  Future<void> _toggleSocialNotifications(bool enabled) async {
    setState(() => _socialNotificationsEnabled = enabled);
    await SocialNotifications.instance?.setEnabled(enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_socialNotifPrefsKey, enabled);
  }

  Future<void> _openSite(String path) async {
    try {
      await launchUrl(
        Uri.parse('${AppConfig.apiBaseUrl}$path'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Defensive, like every other launcher call.
    }
  }

  @override
  Widget build(BuildContext context) {
    final sounds = _soundsEnabled;
    final notifications = _notificationsEnabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionLabel('Preferences'),
            const SizedBox(height: 6),
            // Material (not Container): ListTile ink splashes need a
            // Material ancestor, and a plain colored Container hides them.
            Material(
              color: EnclavdColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: EnclavdColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: sounds == null
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                    )
                  : SwitchListTile(
                      value: sounds,
                      onChanged: _toggleSounds,
                      activeTrackColor: EnclavdColors.primaryButton,
                      secondary: const FaIcon(FontAwesomeIcons.volumeHigh,
                          color: EnclavdColors.link, size: 18),
                      title: const Text('Sound effects'),
                      subtitle: const Text(
                          'Like and action sounds, like on the website'),
                    ),
            ),
            const SizedBox(height: 10),
            Material(
              color: EnclavdColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: EnclavdColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: notifications == null
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                    )
                  : SwitchListTile(
                      value: notifications,
                      onChanged: _toggleNotifications,
                      activeTrackColor: EnclavdColors.primaryButton,
                      secondary: const FaIcon(FontAwesomeIcons.paperPlane,
                          color: EnclavdColors.link, size: 18),
                      title: const Text('Message notifications'),
                      subtitle: const Text(
                          'Device notifications with quick reply when '
                          'someone messages you'),
                    ),
            ),
            const SizedBox(height: 10),
            Material(
              color: EnclavdColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: EnclavdColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _socialNotificationsEnabled == null
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                    )
                  : SwitchListTile(
                      value: _socialNotificationsEnabled!,
                      onChanged: _toggleSocialNotifications,
                      activeTrackColor: EnclavdColors.primaryButton,
                      secondary: const FaIcon(FontAwesomeIcons.bell,
                          color: EnclavdColors.link, size: 18),
                      title: const Text('Notification alerts'),
                      subtitle: const Text(
                          'Likes, comments and mentions, like on the website'),
                    ),
            ),
            // OS-level denial (Android 13+): the toggle can be ON while
            // the system silently drops everything. Surface it here with
            // a one-tap deep link into the OS notification settings.
            if (notifications == true && _osBlocked == true) ...[
              const SizedBox(height: 10),
              Material(
                color: EnclavdColors.card,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: EnclavdColors.warning),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  child: Row(
                    children: [
                      const FaIcon(FontAwesomeIcons.triangleExclamation,
                          color: EnclavdColors.warning, size: 16),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Notifications are blocked on this phone',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            MessageNotifications.instance
                                ?.openOsNotificationSettings(),
                        child: const Text('Open settings',
                            style: TextStyle(
                                fontSize: 13,
                                color: EnclavdColors.link)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const _SectionLabel('Account'),
            const SizedBox(height: 6),
            Material(
              color: EnclavdColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: EnclavdColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const FaIcon(FontAwesomeIcons.userPen,
                        color: EnclavdColors.link, size: 18),
                    title: const Text('Edit profile on the website'),
                    subtitle: const Text('Bio, avatar, password — '
                        'profile-edit on enclavd.com'),
                    trailing: const FaIcon(FontAwesomeIcons.arrowUpRightFromSquare,
                        color: EnclavdColors.textSecondary, size: 14),
                    onTap: () => _openSite('/profile-edit'),
                  ),
                  const Divider(height: 1, color: EnclavdColors.divider),
                  ListTile(
                    leading: const FaIcon(FontAwesomeIcons.inbox,
                        color: EnclavdColors.link, size: 18),
                    title: const Text('Invitations'),
                    subtitle: const Text('Invite friends to Enclavd'),
                    trailing: const FaIcon(FontAwesomeIcons.arrowUpRightFromSquare,
                        color: EnclavdColors.textSecondary, size: 14),
                    onTap: () => _openSite('/invitations'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('About'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: EnclavdColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EnclavdColors.border),
              ),
              child: Column(
                children: [
                  Image.asset('assets/images/enclavd-logo-white.png',
                      height: 22),
                  const SizedBox(height: 10),
                  const Text('Enclavd for Android',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  const Text('Community-built native app',
                      style: TextStyle(
                          color: EnclavdColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => _openSite('/changelog'),
                    icon: const FaIcon(FontAwesomeIcons.scroll,
                        size: 14, color: EnclavdColors.link),
                    label: const Text('What\'s new'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: EnclavdColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}
