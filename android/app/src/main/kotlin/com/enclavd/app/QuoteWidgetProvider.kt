package com.enclavd.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget showing today's quote, with 👍/👎 buttons.
 *
 * The widget NEVER fetches. Content is pushed from Dart (daily background
 * task / foreground refresh) via HomeWidget.saveWidgetData +
 * updateWidget, and the like/dislike buttons deliver their tap to a
 * headless Dart callback (HomeWidgetBackgroundIntent → broadcast →
 * WorkManager job → Dart) carrying the quote id in the URI — the Dart side
 * posts the rating to api/v1/quote with the persisted session, then
 * re-pushes the rated state, which re-renders this provider.
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
        val quoteId = widgetData.getString(KEY_ID, null)
        val rated = widgetData.getString(KEY_RATED, null)

        if (text.isNullOrBlank()) {
            // Freshly added widget, nothing pushed yet — say how to make it
            // come alive instead of showing an empty card.
            views.setTextViewText(
                R.id.quote_widget_text,
                "Open Enclavd to see today's quote",
            )
            views.setViewVisibility(R.id.quote_widget_author, View.GONE)
            views.setViewVisibility(R.id.quote_widget_tags, View.GONE)
            views.setViewVisibility(R.id.quote_widget_actions, View.GONE)
        } else {
            views.setTextViewText(R.id.quote_widget_text, "\u201C$text\u201D")
            views.setTextViewText(R.id.quote_widget_author, "\u2014 $author")
            views.setTextViewText(R.id.quote_widget_tags, tagSpans(tags))
            views.setViewVisibility(R.id.quote_widget_author, View.VISIBLE)
            views.setViewVisibility(R.id.quote_widget_tags, View.VISIBLE)
            renderActions(context, views, quoteId, rated)
        }

        // Tapping the card (outside the buttons) opens the app.
        val openApp =
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        views.setOnClickPendingIntent(R.id.quote_widget_root, openApp)

        appWidgetManager.updateAppWidget(appWidgetIds, views)
    }

    /**
     * Like/dislike row: unrated → both neutral + wired to the Dart rate
     * callback; rated → chosen one tinted (green/red), neither clickable.
     */
    private fun renderActions(
        context: Context,
        views: RemoteViews,
        quoteId: String?,
        rated: String?,
    ) {
        if (rated.isNullOrBlank()) {
            views.setInt(
                R.id.quote_widget_like,
                "setBackgroundResource",
                R.drawable.quote_widget_action_bg,
            )
            views.setInt(
                R.id.quote_widget_dislike,
                "setBackgroundResource",
                R.drawable.quote_widget_action_bg,
            )
            if (!quoteId.isNullOrBlank()) {
                views.setOnClickPendingIntent(
                    R.id.quote_widget_like,
                    HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("enclavdwidget://like?id=$quoteId"),
                    ),
                )
                views.setOnClickPendingIntent(
                    R.id.quote_widget_dislike,
                    HomeWidgetBackgroundIntent.getBroadcast(
                        context,
                        Uri.parse("enclavdwidget://dislike?id=$quoteId"),
                    ),
                )
            }
        } else {
            views.setInt(
                R.id.quote_widget_like,
                "setBackgroundResource",
                if (rated == "like") R.drawable.quote_widget_action_bg_liked
                else R.drawable.quote_widget_action_bg,
            )
            views.setInt(
                R.id.quote_widget_dislike,
                "setBackgroundResource",
                if (rated == "dislike") R.drawable.quote_widget_action_bg_disliked
                else R.drawable.quote_widget_action_bg,
            )
        }
        views.setViewVisibility(R.id.quote_widget_actions, View.VISIBLE)
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
        private const val KEY_ID = "quote_id"
        private const val KEY_RATED = "quote_rated"
    }
}
