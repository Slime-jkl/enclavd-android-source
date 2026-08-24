import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/background_keep_alive.dart';
import '../services/daily_quote_service.dart';
import '../services/message_notifications.dart';
import '../services/push/push_transport.dart';
import '../services/social_notifications.dart';
import '../services/sound_service.dart';
import '../theme/enclavd_theme.dart';

/// App settings — the app-side preferences screen (sounds, notification
/// toggles, keep-alive). Account editing lives in Account settings; the
/// about card lives in the user menu now.
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
  static const _dailyQuotePrefsKey = DailyQuoteService.enabledPrefsKey;

  bool? _soundsEnabled; // null until loaded
  bool? _notificationsEnabled; // null until loaded
  bool? _socialNotificationsEnabled; // null until loaded
  bool? _dailyQuoteEnabled; // null until loaded
  bool? _keepAliveEnabled; // null until loaded
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
    final dailyQuote = prefs.getBool(_dailyQuotePrefsKey) ?? true;
    final keepAlive = await BackgroundKeepAlive.isEnabled();
    if (!mounted) return;
    setState(() {
      _soundsEnabled = enabled;
      _notificationsEnabled = notifications;
      _socialNotificationsEnabled = social;
      _dailyQuoteEnabled = dailyQuote;
      _keepAliveEnabled = keepAlive;
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

  /// Daily quote: on = arm the random-time run (a pending slot is kept);
  /// off = cancel the run so nothing fires until re-enabled.
  Future<void> _toggleDailyQuote(bool enabled) async {
    setState(() => _dailyQuoteEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dailyQuotePrefsKey, enabled);
    if (enabled) {
      await DailyQuoteService.scheduleNextRun();
    } else {
      await DailyQuoteService.cancel();
    }
  }

  Future<void> _toggleKeepAlive(bool enabled) async {
    setState(() => _keepAliveEnabled = enabled);
    await BackgroundKeepAlive.setEnabled(enabled);
  }

  /// Which channel delivers background alerts on THIS device: FCM (Play
  /// builds with Google Play services), Unified Push (any build with a
  /// distributor app installed — the F-Droid path), or the 15-minute
  /// polling fallback when neither is available.
  String get _deliveryModeText {
    final mode = PushManager.instance?.activeLabel;
    if (mode != null && mode != PushManager.fallbackLabel) {
      return '$mode — instant background alerts';
    }
    return '15-minute background checks — install a Unified Push '
        'distributor (ntfy, Conversations, NextPush) for instant alerts';
  }

  @override
  Widget build(BuildContext context) {
    final sounds = _soundsEnabled;
    final notifications = _notificationsEnabled;
    return Scaffold(
      appBar: AppBar(title: const Text('App settings')),
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
            const SizedBox(height: 10),
            Material(
              color: EnclavdColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: EnclavdColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: _dailyQuoteEnabled == null
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
                      value: _dailyQuoteEnabled!,
                      onChanged: _toggleDailyQuote,
                      activeTrackColor: EnclavdColors.primaryButton,
                      secondary: const FaIcon(FontAwesomeIcons.quoteLeft,
                          color: EnclavdColors.link, size: 18),
                      title: const Text('Daily quote'),
                      subtitle: const Text(
                          'Today\u2019s quote as a home-screen widget and one '
                          'notification a day at a random time'),
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
              child: _keepAliveEnabled == null
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
                      value: _keepAliveEnabled!,
                      onChanged: _toggleKeepAlive,
                      activeTrackColor: EnclavdColors.primaryButton,
                      secondary: const FaIcon(FontAwesomeIcons.bolt,
                          color: EnclavdColors.link, size: 18),
                      title: const Text('Live updates while minimized'),
                      subtitle: const Text(
                          'Keep notifications and messages flowing while '
                          'the app is in the background (shows a small '
                          '"Enclavd" notice while active)'),
                    ),
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 10),
            // Delivery mode is an implementation detail (auto-resolved at
            // startup: FCM → Unified Push → 15-min poll), so it is a
            // read-only status row, not a toggle. Placed LAST so the
            // OS-blocked warning above stays above the fold on small
            // screens.
            Material(
              color: EnclavdColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: EnclavdColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const FaIcon(FontAwesomeIcons.towerBroadcast,
                    color: EnclavdColors.link, size: 18),
                title: const Text('Push delivery'),
                subtitle: Text(_deliveryModeText,
                    style: const TextStyle(fontSize: 12.5)),
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
