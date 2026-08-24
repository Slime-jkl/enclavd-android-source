import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/daily_quote_service.dart';
import '../services/daily_quote_widget.dart';
import '../theme/enclavd_theme.dart';
import 'quote_help_screen.dart';

/// Quote of the day — the feature's own settings screen (reachable from
/// the user menu's dedicated "Quote of the day" entry and from the widget
/// / notification deep link). Holds the master toggle for the daily-quote
/// pipeline and the widget's display options; the generic App settings
/// screen no longer mixes these in.
class QuoteSettingsScreen extends StatefulWidget {
  const QuoteSettingsScreen({super.key});

  static const routeName = '/quote-settings';

  @override
  State<QuoteSettingsScreen> createState() => _QuoteSettingsScreenState();
}

class _QuoteSettingsScreenState extends State<QuoteSettingsScreen> {
  static const _dailyQuotePrefsKey = DailyQuoteService.enabledPrefsKey;

  bool? _dailyQuoteEnabled; // null until loaded
  bool? _widgetShowTags; // null until loaded
  bool? _widgetLight; // null until loaded
  bool? _widgetFollowSystem; // null until loaded

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dailyQuote = prefs.getBool(_dailyQuotePrefsKey) ?? true;
    // Widget display prefs live in home_widget's storage — the same source
    // the native provider renders from. Read through the service so a
    // plugin hiccup degrades to defaults instead of throwing.
    final showTags = await DailyQuoteWidget.showTags();
    final light = await DailyQuoteWidget.lightMode();
    final followSystem = await DailyQuoteWidget.followsSystemTheme();
    if (!mounted) return;
    setState(() {
      _dailyQuoteEnabled = dailyQuote;
      _widgetShowTags = showTags;
      _widgetLight = light;
      _widgetFollowSystem = followSystem;
    });
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

  /// Widget display prefs: each toggle persists to the widget storage and
  /// re-renders the pinned widget immediately. (The logo has no toggle —
  /// it is always on by design.)
  Future<void> _toggleWidgetShowTags(bool enabled) async {
    setState(() => _widgetShowTags = enabled);
    await DailyQuoteWidget.setDisplayPrefs(showTags: enabled);
  }

  Future<void> _toggleWidgetFollowSystem(bool enabled) async {
    setState(() => _widgetFollowSystem = enabled);
    await DailyQuoteWidget.setDisplayPrefs(followSystem: enabled);
  }

  Future<void> _toggleWidgetLight(bool enabled) async {
    setState(() => _widgetLight = enabled);
    await DailyQuoteWidget.setDisplayPrefs(light: enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quote of the day')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _SectionLabel('Daily quote'),
            const SizedBox(height: 6),
            _toggleRow(
              loading: _dailyQuoteEnabled == null,
              value: _dailyQuoteEnabled ?? true,
              onChanged: _toggleDailyQuote,
              icon: FontAwesomeIcons.quoteLeft,
              title: 'Daily quote',
              subtitle: 'Today\u2019s quote on your home screen, plus a '
                  'notification at a random time when no widget is added',
            ),
            const SizedBox(height: 10),
            const _SectionLabel('Widget'),
            const SizedBox(height: 6),
            _toggleRow(
              loading: _widgetShowTags == null,
              value: _widgetShowTags ?? true,
              onChanged: _toggleWidgetShowTags,
              icon: FontAwesomeIcons.tags,
              title: 'Show tags',
              subtitle: 'Display the quote\u2019s tags on the widget',
            ),
            const SizedBox(height: 10),
            _toggleRow(
              loading: _widgetFollowSystem == null,
              value: _widgetFollowSystem ?? true,
              onChanged: _toggleWidgetFollowSystem,
              icon: FontAwesomeIcons.moon,
              title: 'Follow system theme',
              subtitle: 'Match your phone\u2019s light/dark mode',
            ),
            const SizedBox(height: 10),
            _toggleRow(
              loading: _widgetLight == null,
              value: _widgetLight ?? false,
              // Manual light/dark is only meaningful when the card is NOT
              // following the system theme — greyed out otherwise.
              enabled: _widgetFollowSystem == false,
              onChanged: _toggleWidgetLight,
              icon: FontAwesomeIcons.sun,
              title: 'Light variant',
              subtitle: (_widgetFollowSystem ?? true)
                  ? 'Turn off \u2018Follow system theme\u2019 to choose'
                  : 'Light card instead of the dark one',
            ),
            const SizedBox(height: 10),
            Material(
              color: EnclavdColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: EnclavdColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const FaIcon(FontAwesomeIcons.circleQuestion,
                    color: EnclavdColors.link, size: 18),
                title: const Text('How daily quotes work'),
                subtitle: const Text('The short version'),
                trailing: const Icon(Icons.chevron_right,
                    color: EnclavdColors.border),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const QuoteHelpScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // The logo has no toggle — it is always on (the white-house
            // watermark). A quiet note keeps that from reading as a bug.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'The Enclavd logo is always shown on the widget.',
                style: TextStyle(
                    color: EnclavdColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One settings row with the loading-skeleton fallback (the screen shows
  /// real values once the prefs land; never a bare static placeholder).
  /// [enabled] false = the row is dimmed and not tappable (the manual
  /// Light variant while the widget follows the system theme).
  Widget _toggleRow({
    required bool loading,
    required bool value,
    required ValueChanged<bool> onChanged,
    required FaIconData icon,
    required String title,
    required String subtitle,
    bool enabled = true,
  }) {
    return Material(
      color: EnclavdColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: EnclavdColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          : Opacity(
              opacity: enabled ? 1 : 0.45,
              child: SwitchListTile(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeTrackColor: EnclavdColors.primaryButton,
                secondary: FaIcon(icon, color: EnclavdColors.link, size: 18),
                title: Text(title),
                subtitle: Text(subtitle),
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
