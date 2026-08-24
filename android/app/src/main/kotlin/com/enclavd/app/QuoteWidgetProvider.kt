package com.enclavd.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget showing today's quote.
 *
 * Passive by design: the widget NEVER fetches anything. Content is pushed
 * from Dart (the daily background task and the app foreground refresh) via
 * HomeWidget.saveWidgetData + HomeWidget.updateWidget — home_widget stores
 * the fields in the widget's own SharedPreferences and delivers this
 * provider's onUpdate. All this class does is render the stored data.
 */
class QuoteWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = RemoteViews(context.packageName, R.layout.enclavd_quote_widget)
        val text = widgetData.getString(KEY_TEXT, null)
        val author = widgetData.getString(KEY_AUTHOR, null).orEmpty()
        val tags = widgetData.getString(KEY_TAGS, null).orEmpty()
            .split('|')
            .filter { it.isNotBlank() }

        if (text.isNullOrBlank()) {
            // Freshly added widget, nothing pushed yet — say how to make it
            // come alive instead of showing an empty card.
            views.setTextViewText(
                R.id.quote_widget_text,
                "Open Enclavd to see today's quote",
            )
            views.setViewVisibility(R.id.quote_widget_author, View.GONE)
            views.setViewVisibility(R.id.quote_widget_tags, View.GONE)
        } else {
            views.setTextViewText(R.id.quote_widget_text, "\u201C$text\u201D")
            views.setTextViewText(R.id.quote_widget_author, "\u2014 $author")
            views.setTextViewText(R.id.quote_widget_tags, tagSpans(tags))
            views.setViewVisibility(R.id.quote_widget_author, View.VISIBLE)
            views.setViewVisibility(R.id.quote_widget_tags, View.VISIBLE)
        }

        // Tapping the card opens the app (home_widget's launcher intent).
        val openApp =
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        views.setOnClickPendingIntent(R.id.quote_widget_root, openApp)

        appWidgetManager.updateAppWidget(appWidgetIds, views)
    }

    /** "#" in the brand blue (blue-500), tag names in muted gray. */
    private fun tagSpans(tags: List<String>): SpannableString {
        val label = tags.joinToString("  ") { "#$it" }
        val spannable = SpannableString(label)
        var index = 0
        for (tag in tags) {
            spannable.setSpan(
                ForegroundColorSpan(Color.rgb(59, 130, 246)),
                index,
                index + 1,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
            index += tag.length + 3 // "#tag" + the two separating spaces
        }
        return spannable
    }

    companion object {
        private const val KEY_TEXT = "quote_text"
        private const val KEY_AUTHOR = "quote_author"
        private const val KEY_TAGS = "quote_tags"
    }
}
