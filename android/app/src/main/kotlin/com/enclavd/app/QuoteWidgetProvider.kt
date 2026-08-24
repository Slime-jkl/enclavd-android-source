package com.enclavd.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget showing today's quote, with 👍/👎 buttons.
 *
 * The widget NEVER fetches. Content is pushed from Dart (daily background
 * task / foreground refresh) via HomeWidget.saveWidgetData +
 * updateWidget; the like/dislike buttons deliver their tap to a headless
 * Dart callback (HomeWidgetBackgroundIntent → broadcast → WorkManager job
 * → Dart) carrying the quote id in the URI. Display preferences (show
 * tags / show logo / light variant) are ALSO widget data, toggled from the
 * app's Settings — every render reads them from the same source.
 *
 * Text sizes scale with the widget's current width (dp), read from the
 * launcher's options; onAppWidgetOptionsChanged re-renders on resize.
 */
class QuoteWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        render(context, appWidgetManager, appWidgetIds, widgetData)
    }

    /** The launcher resized the widget — re-render at the new size. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        render(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        data: SharedPreferences,
    ) {
        val text = data.getString(KEY_TEXT, null)
        val author = data.getString(KEY_AUTHOR, null).orEmpty()
        val tags = data.getString(KEY_TAGS, null).orEmpty()
            .split('|')
            .filter { it.isNotBlank() }
        val quoteId = data.getString(KEY_ID, null)
        val rated = data.getString(KEY_RATED, null)

        val showTags = data.getBoolean(KEY_SHOW_TAGS, true)
        val showLogo = data.getBoolean(KEY_SHOW_LOGO, true)
        val light = data.getBoolean(KEY_LIGHT, false)

        for (widgetId in appWidgetIds) {
            val widthDp = appWidgetManager
                .getAppWidgetOptions(widgetId)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
            val views = RemoteViews(context.packageName, R.layout.enclavd_quote_widget)
            applyColors(views, light)
            applyTextSizes(views, widthDp)

            if (text.isNullOrBlank()) {
                // Freshly added widget, nothing pushed yet — say how to make
                // it come alive instead of showing an empty card.
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
                views.setTextViewText(R.id.quote_widget_tags, tagSpans(tags, light))
                views.setViewVisibility(R.id.quote_widget_author, View.VISIBLE)
                views.setViewVisibility(
                    R.id.quote_widget_tags,
                    if (showTags) View.VISIBLE else View.GONE,
                )
                renderActions(context, views, quoteId, rated, light)
            }

            // Logo + label header: logo toggleable, hidden on the placeholder.
            views.setImageViewResource(
                R.id.quote_widget_logo,
                if (light) R.drawable.quote_widget_logo_dark
                else R.drawable.quote_widget_logo,
            )
            views.setViewVisibility(
                R.id.quote_widget_logo,
                if (showLogo) View.VISIBLE else View.GONE,
            )

            // Tapping the card (outside the buttons) opens the app.
            val openApp =
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            views.setOnClickPendingIntent(R.id.quote_widget_root, openApp)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /** Dark (default) vs light card: background, text colors, logo glyph. */
    private fun applyColors(views: RemoteViews, light: Boolean) {
        views.setInt(
            R.id.quote_widget_root,
            "setBackgroundResource",
            if (light) R.drawable.quote_widget_bg_light
            else R.drawable.quote_widget_bg,
        )
        views.setTextColor(
            R.id.quote_widget_label,
            if (light) Color.rgb(107, 114, 128) else Color.rgb(156, 163, 175),
        )
        views.setTextColor(
            R.id.quote_widget_text,
            if (light) Color.rgb(17, 24, 39) else Color.rgb(229, 231, 235),
        )
        views.setTextColor(
            R.id.quote_widget_author,
            if (light) Color.rgb(107, 114, 128) else Color.rgb(156, 163, 175),
        )
        views.setTextColor(
            R.id.quote_widget_tags,
            if (light) Color.rgb(107, 114, 128) else Color.rgb(156, 163, 175),
        )
    }

    /** Text scales with the widget width: compact at min, roomier when big. */
    private fun applyTextSizes(views: RemoteViews, widthDp: Int) {
        val (text, author, tags, label) = when {
            widthDp >= 500 -> Sizes(19f, 15f, 13f, 12f)
            widthDp >= 320 -> Sizes(16f, 13f, 12f, 11f)
            else -> Sizes(14f, 12f, 11f, 10f)
        }
        views.setTextViewTextSize(R.id.quote_widget_text, TypedValue.COMPLEX_UNIT_SP, text)
        views.setTextViewTextSize(R.id.quote_widget_author, TypedValue.COMPLEX_UNIT_SP, author)
        views.setTextViewTextSize(R.id.quote_widget_tags, TypedValue.COMPLEX_UNIT_SP, tags)
        views.setTextViewTextSize(R.id.quote_widget_label, TypedValue.COMPLEX_UNIT_SP, label)
    }

    private data class Sizes(
        val text: Float,
        val author: Float,
        val tags: Float,
        val label: Float,
    )

    /**
     * Like/dislike row: unrated → both neutral + wired to the Dart rate
     * callback; rated → chosen one tinted (green/red), neither clickable.
     */
    private fun renderActions(
        context: Context,
        views: RemoteViews,
        quoteId: String?,
        rated: String?,
        light: Boolean,
    ) {
        val neutralBg =
            if (light) R.drawable.quote_widget_action_bg_light
            else R.drawable.quote_widget_action_bg
        if (rated.isNullOrBlank()) {
            views.setInt(R.id.quote_widget_like, "setBackgroundResource", neutralBg)
            views.setInt(R.id.quote_widget_dislike, "setBackgroundResource", neutralBg)
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
                else neutralBg,
            )
            views.setInt(
                R.id.quote_widget_dislike,
                "setBackgroundResource",
                if (rated == "dislike") R.drawable.quote_widget_action_bg_disliked
                else neutralBg,
            )
        }
        views.setViewVisibility(R.id.quote_widget_actions, View.VISIBLE)
    }

    /** "#" in the brand blue (blue-600 on light for contrast), names muted. */
    private fun tagSpans(tags: List<String>, light: Boolean): SpannableString {
        val label = tags.joinToString("  ") { "#$it" }
        val spannable = SpannableString(label)
        val hashColor =
            if (light) Color.rgb(37, 99, 235) else Color.rgb(59, 130, 246)
        var index = 0
        for (tag in tags) {
            spannable.setSpan(
                ForegroundColorSpan(hashColor),
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
        private const val KEY_SHOW_TAGS = "widget_show_tags"
        private const val KEY_SHOW_LOGO = "widget_show_logo"
        private const val KEY_LIGHT = "widget_light"
    }
}
