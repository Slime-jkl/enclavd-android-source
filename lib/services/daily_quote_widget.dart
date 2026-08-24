import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Home-screen widget showing today's quote (Android AppWidget).
///
/// The widget itself is native: `android/.../QuoteWidgetProvider.kt` renders
/// `res/layout/enclavd_quote_widget.xml` from data it reads out of the
/// widget's SharedPreferences. This class is the ONLY Dart-side writer —
/// every path that has fresh quote data (the daily background task and the
/// app foreground refresh) funnels through [push].
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

  /// Saves the quote fields and asks the launcher to re-render the widget.
  /// Silent on failure — a widget hiccup must never break the caller
  /// (e.g. the daily notification flow).
  static Future<void> push({
    required String text,
    required String author,
    required List<String> tags,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>(keyText, text);
      await HomeWidget.saveWidgetData<String>(keyAuthor, author);
      await HomeWidget.saveWidgetData<String>(keyTags, tags.join('|'));
      await HomeWidget.updateWidget(
        name: widgetName,
        androidName: widgetAndroidName,
      );
    } catch (e) {
      debugPrint('quote widget: update failed: $e');
    }
  }
}
