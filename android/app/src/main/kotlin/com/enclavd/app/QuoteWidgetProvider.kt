package com.enclavd.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
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

class QuoteWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        render(context, appWidgetManager, appWidgetIds, widgetData)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?,
    ) {
        render(context, appWidgetManager, intArrayOf(appWidgetId), HomeWidgetPlugin.getData(context))
    }

    /** Re-render all pinned widgets, also when the system theme changes. */
    internal fun render(
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
        val followSystem = data.getBoolean(KEY_FOLLOW_SYSTEM, true)
        val light = if (followSystem) !isNight(context)
        else data.getBoolean(KEY_LIGHT, false)

        for (widgetId in appWidgetIds) {
            val options = appWidgetManager.getAppWidgetOptions(widgetId)
            val widthDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
            val heightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
            val views = RemoteViews(context.packageName, R.layout.enclavd_quote_widget)
            applyColors(views, light)
            applySizes(views, widthDp, heightDp)

            if (text.isNullOrBlank()) {
                views.setTextViewText(
                    R.id.quote_widget_text,
                    "Open Enclavd to see today's quote",
                )
                views.setViewVisibility(R.id.quote_widget_mark, View.GONE)
                views.setViewVisibility(R.id.quote_widget_close_mark, View.GONE)
                views.setViewVisibility(R.id.quote_widget_author, View.GONE)
                views.setViewVisibility(R.id.quote_widget_tags, View.GONE)
                views.setViewVisibility(R.id.quote_widget_actions, View.GONE)
                views.setViewVisibility(R.id.quote_widget_rated, View.GONE)
            } else {
                views.setTextViewText(R.id.quote_widget_text, text)
                views.setTextViewText(R.id.quote_widget_author, "- $author")
                views.setTextViewText(R.id.quote_widget_tags, tagSpans(tags, light))
                views.setViewVisibility(R.id.quote_widget_mark, View.VISIBLE)
                views.setViewVisibility(R.id.quote_widget_close_mark, View.VISIBLE)
                views.setViewVisibility(R.id.quote_widget_author, View.VISIBLE)
                views.setViewVisibility(
                    R.id.quote_widget_tags,
                    if (showTags) View.VISIBLE else View.GONE,
                )
                renderActions(context, views, quoteId, rated, light)
            }

            views.setImageViewResource(
                R.id.quote_widget_watermark,
                if (light) R.drawable.quote_widget_logo_dark
                else R.drawable.quote_widget_logo,
            )
            views.setImageViewResource(
                R.id.quote_widget_wordmark,
                if (light) R.drawable.enclavd_logo_dark
                else R.drawable.enclavd_logo_white,
            )
            // Watermark at ~5% opacity (13/255).
            views.setInt(R.id.quote_widget_watermark, "setImageAlpha", 13)

            // Opens the quote-settings screen (deep link resolved in Dart).
            val openApp = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("enclavdwidget://quote-settings"),
            )
            views.setOnClickPendingIntent(R.id.quote_widget_root, openApp)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

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
        // Brand blue, deeper on light for contrast.
        val markColor =
            if (light) Color.rgb(37, 99, 235) else Color.rgb(59, 130, 246)
        views.setTextColor(R.id.quote_widget_mark, markColor)
        views.setTextColor(R.id.quote_widget_close_mark, markColor)
    }

    private fun applySizes(views: RemoteViews, widthDp: Int, heightDp: Int) {
        val scale = (widthDp / 360f).coerceIn(0.7f, 1.5f)
        val text = 20f * scale
        val mark = 31f * scale
        val author = 13f * scale
        val tags = 12f * scale
        val label = 11f * scale
        val rated = 18f * scale
        val actionEmoji = 16f * scale
        views.setTextViewTextSize(R.id.quote_widget_text, TypedValue.COMPLEX_UNIT_SP, text)
        views.setTextViewTextSize(R.id.quote_widget_mark, TypedValue.COMPLEX_UNIT_SP, mark)
        views.setTextViewTextSize(R.id.quote_widget_close_mark, TypedValue.COMPLEX_UNIT_SP, mark)
        views.setTextViewTextSize(R.id.quote_widget_author, TypedValue.COMPLEX_UNIT_SP, author)
        views.setTextViewTextSize(R.id.quote_widget_tags, TypedValue.COMPLEX_UNIT_SP, tags)
        views.setTextViewTextSize(R.id.quote_widget_label, TypedValue.COMPLEX_UNIT_SP, label)
        views.setTextViewTextSize(R.id.quote_widget_rated, TypedValue.COMPLEX_UNIT_SP, rated)

        views.setViewLayoutWidth(R.id.quote_widget_like, 44f * scale, TypedValue.COMPLEX_UNIT_DIP)
        views.setViewLayoutHeight(R.id.quote_widget_like, 36f * scale, TypedValue.COMPLEX_UNIT_DIP)
        views.setViewLayoutWidth(R.id.quote_widget_dislike, 44f * scale, TypedValue.COMPLEX_UNIT_DIP)
        views.setViewLayoutHeight(R.id.quote_widget_dislike, 36f * scale, TypedValue.COMPLEX_UNIT_DIP)
        views.setTextViewTextSize(R.id.quote_widget_like, TypedValue.COMPLEX_UNIT_SP, actionEmoji)
        views.setTextViewTextSize(R.id.quote_widget_dislike, TypedValue.COMPLEX_UNIT_SP, actionEmoji)

        // Wordmark (1584x231 aspect): fixed, about label height.
        val wordmarkHeightDp = 16f
        val wordmarkWidthDp = wordmarkHeightDp * 1584f / 231f
        views.setViewLayoutWidth(
            R.id.quote_widget_wordmark,
            wordmarkWidthDp,
            TypedValue.COMPLEX_UNIT_DIP,
        )
        views.setViewLayoutHeight(
            R.id.quote_widget_wordmark,
            wordmarkHeightDp,
            TypedValue.COMPLEX_UNIT_DIP,
        )
        // ~85% of the smaller side (faint texture, so generous is fine).
        val watermarkDp = (minOf(widthDp, heightDp) * 0.85f).coerceIn(48f, 260f)
        views.setViewLayoutWidth(
            R.id.quote_widget_watermark,
            watermarkDp,
            TypedValue.COMPLEX_UNIT_DIP,
        )
        views.setViewLayoutHeight(
            R.id.quote_widget_watermark,
            watermarkDp,
            TypedValue.COMPLEX_UNIT_DIP,
        )

        // Narrow card: the wordmark takes over from the label.
        views.setViewVisibility(
            R.id.quote_widget_label,
            if (widthDp >= 260) View.VISIBLE else View.GONE,
        )
    }

    private fun isNight(context: Context): Boolean {
        val mode =
            context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return mode == Configuration.UI_MODE_NIGHT_YES
    }

    private fun renderActions(
        context: Context,
        views: RemoteViews,
        quoteId: String?,
        rated: String?,
        light: Boolean,
    ) {
        if (rated.isNullOrBlank()) {
            val neutralBg =
                if (light) R.drawable.quote_widget_action_bg_light
                else R.drawable.quote_widget_action_bg
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
            views.setViewVisibility(R.id.quote_widget_actions, View.VISIBLE)
            views.setViewVisibility(R.id.quote_widget_rated, View.GONE)
        } else {
            views.setViewVisibility(R.id.quote_widget_actions, View.GONE)
            views.setViewVisibility(R.id.quote_widget_rated, View.VISIBLE)
            views.setTextViewText(
                R.id.quote_widget_rated,
                if (rated == "like") "\uD83D\uDC4D" else "\uD83D\uDC4E",
            )
            views.setTextColor(
                R.id.quote_widget_rated,
                if (light) Color.rgb(107, 114, 128) else Color.rgb(156, 163, 175),
            )
        }
    }

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
        private const val KEY_LIGHT = "widget_light"
        private const val KEY_FOLLOW_SYSTEM = "widget_follow_system"
    }
}
