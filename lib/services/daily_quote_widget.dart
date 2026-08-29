import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Snapshot of the quote currently pushed to the widget (what the home
/// screen shows right now), read back from widget storage.
class WidgetQuote {
  const WidgetQuote({
    required this.text,
    required this.author,
    required this.tags,
    required this.id,
    this.rated,
  });

  final String text;
  final String author;
  final List<String> tags;
  final int id;
  final String? rated; // 'like' | 'dislike' | null
}

/// Home-screen widget showing today's quote (Android AppWidget).
class DailyQuoteWidget {
  DailyQuoteWidget._();

  /// `androidName` must match the provider class name; `name` is the
  /// fallback lookup (home_widget contract).
  static const String widgetName = 'EnclavdQuote';
  static const String widgetAndroidName = 'QuoteWidgetProvider';

  /// Keys written into the widget SharedPreferences - read by the provider.
  static const String keyText = 'quote_text';
  static const String keyAuthor = 'quote_author';
  static const String keyTags = 'quote_tags';
  static const String keyId = 'quote_id';
  static const String keyRated = 'quote_rated';

  /// Display-preference keys (toggled in the Quote of the day settings);
  /// the native provider reads them from the same widget storage, so a
  /// toggle re-renders. The logo has NO key: always on by design.
  static const String keyShowTags = 'widget_show_tags';
  static const String keyLight = 'widget_light';

  /// When true (default) the widget's light/dark look follows the SYSTEM
  /// theme; `keyLight` is then only a manual override, used when this is
  /// switched off.
  static const String keyFollowSystem = 'widget_follow_system';

  static Future<bool> showTags() async {
    try {
      return await HomeWidget.getWidgetData<bool>(keyShowTags,
              defaultValue: true) ??
          true;
    } catch (e) {
      return true; // plugin unavailable (tests) -> defaults
    }
  }

  static Future<bool> lightMode() async {
    try {
      return await HomeWidget.getWidgetData<bool>(keyLight,
              defaultValue: false) ??
          false;
    } catch (e) {
      return false;
    }
  }

  /// Whether the widget follows the system light/dark theme (default true).
  static Future<bool> followsSystemTheme() async {
    try {
      return await HomeWidget.getWidgetData<bool>(keyFollowSystem,
              defaultValue: true) ??
          true;
    } catch (e) {
      return true;
    }
  }

  /// The quote on the widget right now; null when nothing was pushed yet.
  /// Used by the settings preview so it mirrors the home screen exactly.
  static Future<WidgetQuote?> current() async {
    try {
      final text = await HomeWidget.getWidgetData<String>(keyText) ?? '';
      if (text.isEmpty) return null;
      final rated = await HomeWidget.getWidgetData<String>(keyRated) ?? '';
      return WidgetQuote(
        text: text,
        author: await HomeWidget.getWidgetData<String>(keyAuthor) ?? '',
        tags: (await HomeWidget.getWidgetData<String>(keyTags) ?? '')
            .split('|')
            .where((t) => t.isNotEmpty)
            .toList(),
        id: int.tryParse(
                await HomeWidget.getWidgetData<String>(keyId) ?? '') ??
            0,
        rated: rated.isEmpty ? null : rated,
      );
    } catch (e) {
      debugPrint('quote widget: read failed: $e');
      return null;
    }
  }

  /// Persists the display prefs and re-renders the widget; silent on
  /// failure, like every other widget call.
  static Future<void> setDisplayPrefs({
    bool? showTags,
    bool? light,
    bool? followSystem,
  }) async {
    try {
      if (showTags != null) {
        await HomeWidget.saveWidgetData<bool>(keyShowTags, showTags);
      }
      if (light != null) {
        await HomeWidget.saveWidgetData<bool>(keyLight, light);
      }
      if (followSystem != null) {
        await HomeWidget.saveWidgetData<bool>(keyFollowSystem, followSystem);
      }
      await HomeWidget.updateWidget(
        name: widgetName,
        androidName: widgetAndroidName,
      );
    } catch (e) {
      debugPrint('quote widget: display prefs failed: $e');
    }
  }

  /// Saves the quote fields (incl. the quote id the rate buttons need and
  /// the current rated state) and asks the launcher to re-render. Returns
  /// true ONLY when the whole push succeeded - callers must not treat a
  /// failed push as done (a swallowed failure would advance the freshness
  /// stamp without the widget ever updating). Silent on failure so a
  /// widget hiccup never breaks the caller.
  static Future<bool> push({
    required String text,
    required String author,
    required List<String> tags,
    required int quoteId,
    String? rated,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>(keyText, text);
      await HomeWidget.saveWidgetData<String>(keyAuthor, author);
      await HomeWidget.saveWidgetData<String>(keyTags, tags.join('|'));
      await HomeWidget.saveWidgetData<String>(keyId, '$quoteId');
      await HomeWidget.saveWidgetData<String>(keyRated, rated ?? '');
      await HomeWidget.updateWidget(
        name: widgetName,
        androidName: widgetAndroidName,
      );
      return true;
    } catch (e) {
      debugPrint('quote widget: update failed: $e');
      return false;
    }
  }

  /// Reflects a fresh rating on the widget (from the background rate flow):
  /// updates only the id + rated fields, then re-renders - the text/tags
  /// already on the widget stay untouched.
  static Future<void> markRated({
    required int quoteId,
    required String rated,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>(keyId, '$quoteId');
      await HomeWidget.saveWidgetData<String>(keyRated, rated);
      await HomeWidget.updateWidget(
        name: widgetName,
        androidName: widgetAndroidName,
      );
    } catch (e) {
      debugPrint('quote widget: markRated failed: $e');
    }
  }
}
