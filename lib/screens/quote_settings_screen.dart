import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/daily_quote_service.dart';
import '../services/daily_quote_widget.dart';
import '../theme/enclavd_theme.dart';
import '../widgets/quote_widget_preview.dart';
import 'quote_help_screen.dart';

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
  WidgetQuote? _widgetQuote; // what the pinned widget shows right now
  TodayQuote? _today; // fresh fallback when nothing is pushed yet
  bool _quoteLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final dailyQuote = prefs.getBool(_dailyQuotePrefsKey) ?? true;
    // Widget prefs live in home_widget storage, read via the service so a
    // plugin hiccup degrades to defaults instead of throwing.
    final showTags = await DailyQuoteWidget.showTags();
    final light = await DailyQuoteWidget.lightMode();
    final followSystem = await DailyQuoteWidget.followsSystemTheme();
    // Preview mirrors the widget
    final widgetQuote = await DailyQuoteWidget.current();
    final today =
        widgetQuote == null ? await DailyQuoteService.fetchToday() : null;
    if (!mounted) return;
    setState(() {
      _dailyQuoteEnabled = dailyQuote;
      _widgetShowTags = showTags;
      _widgetLight = light;
      _widgetFollowSystem = followSystem;
      _widgetQuote = widgetQuote;
      _today = today;
      _quoteLoading = false;
    });
  }

  Future<void> _toggleDailyQuote(bool enabled) async {
    setState(() => _dailyQuoteEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dailyQuotePrefsKey, enabled);
    if (enabled) {
      await DailyQuoteService.scheduleNextRun();
      // Drop the freshness stamp and refresh so re-enabling gives instant feedback.
      unawaited(DailyQuoteService.refreshWidgetNow());
    } else {
      await DailyQuoteService.cancel();
    }
  }

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
                title: const Text('How daily quotes work?'),
                trailing: const Icon(Icons.chevron_right,
                    color: EnclavdColors.border),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const QuoteHelpScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const _SectionLabel('Widget Preview'),
            const SizedBox(height: 6),
            _preview(),
            const SizedBox(height: 18),
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
              // Light/dark only matters when not following the system theme.
              enabled: _widgetFollowSystem == false,
              onChanged: _toggleWidgetLight,
              icon: FontAwesomeIcons.sun,
              title: 'Light variant',
              subtitle: (_widgetFollowSystem ?? true)
                  ? 'Turn off \u2018Follow system theme\u2019 to choose'
                  : 'Light card instead of the dark one',
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    if (_quoteLoading) {
      return const SizedBox(
        height: 160,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final quote = _widgetQuote;
    final today = _today;
    final light = (_widgetFollowSystem ?? true)
        ? MediaQuery.platformBrightnessOf(context) == Brightness.light
        : (_widgetLight ?? false);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: QuoteWidgetPreview(
          text: quote?.text ?? today?.quote.text,
          author: quote?.author ?? today?.quote.author ?? '',
          tags: quote?.tags ?? today?.quote.tags ?? const [],
          rated: quote?.rated ?? today?.rated,
          showTags: _widgetShowTags ?? true,
          light: light,
        ),
      ),
    );
  }

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
