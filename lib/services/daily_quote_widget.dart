import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Home-screen widget showing today's quote (Android AppWidget).
///
/// The widget itself is native: `android/.../QuoteWidgetProvider.kt` renders
/// `res/layout/enclavd_quote_widget.xml` (quote + author + #tags + 👍/👎
/// buttons) from data it reads out of the widget's SharedPreferences. This
/// class is the ONLY Dart-side writer — every path that has fresh quote
/// data (the daily background task, the app foreground refresh, and the
/// background rating flow) funnels through here.
class DailyQuoteWidget {
  DailyQuoteWidget._();

  /// The widget's identity: `androidName` must match the provider class
  /// name, `name` is the fallback lookup (home_widget contract).
  static const String widgetName = 'EnclavdQuote';
  static const String widgetAndroidName = 'QuoteWidgetProvider';

  /// Keys written into the widget SharedPreferences — read by the provider.
  static const String keyText = 'quote_text';
  static const String keyAuthor = 'quote_author';
  static const String keyTags = 'quote_tags';
  static const String keyId = 'quote_id';
  static const String keyRated = 'quote_rated';

  /// Full refresh: saves the quote fields (including the quote id the rate
  /// buttons need and the current rated state) and asks the launcher to
  /// re-render. Silent on failure — a widget hiccup must never break the
  /// caller (e.g. the daily notification flow).
  static Future<void> push({
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
    } catch (e) {
      debugPrint('quote widget: update failed: $e');
    }
  }

  /// Reflects a fresh rating on the widget (from the background rate flow):
  /// updates only the id + rated fields, then re-renders — the text/tags
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
