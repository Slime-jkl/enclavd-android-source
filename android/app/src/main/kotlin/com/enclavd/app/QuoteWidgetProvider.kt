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

/**
 * Home-screen widget showing today's quote, with 👍/👎 buttons.
 *
 * The widget NEVER fetches. Content is pushed from Dart (daily background
 * task / foreground refresh) via HomeWidget.saveWidgetData +
 * updateWidget; the like/dislike buttons deliver their tap to a headless
 * Dart callback (HomeWidgetBackgroundIntent → broadcast → WorkManager job
 * → Dart) carrying the quote id in the URI. Display preferences (show
 * tags / light variant / follow system theme) are ALSO widget data,
 * toggled from the app's Quote of the day settings — every render reads
 * them from the same source.
 *
 * Design ("white-house document"): the logo is ALWAYS on — a large
 * ~5%-opacity watermark of the app icon in the middle of the card with
 * the quote text over it, plus the app header's wordmark at the top
 * right (small and fixed; it takes over the "QUOTE OF THE DAY" title on
 * narrow widgets). The quote renders without wrapping quotation marks;
 * a large blue stylized " mark sits above it and its mirror, the
 * closing ", in the bottom-right corner. After a vote the buttons
 * disappear and a single 👍/👎 emoji — the choice itself — marks the
 * rating. The card follows the SYSTEM light/dark theme by default
 * (QuoteWidgetConfigReceiver re-renders it when the theme flips).
 *
 * All sizes scale seamlessly with the widget's current width (dp): one
 * continuous scale factor drives every element, so resizing the widget
 * scales the whole card proportionally. onAppWidgetOptionsChanged
 * re-renders on resize.
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

    /** Re-render all pinned widgets (also called by QuoteWidgetConfigReceiver
     *  when the system light/dark theme changes). */
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
        // Follow the SYSTEM light/dark mode by default; the manual light
        // variant is only used when system-follow is switched off.
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
                // Freshly added widget, nothing pushed yet — say how to make
                // it come alive instead of showing an empty card.
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
                // No wrapping quotes — the big blue marks carry the
                // quotation styling now (opening above, closing bottom-right).
                views.setTextViewText(R.id.quote_widget_text, text)
                views.setTextViewText(R.id.quote_widget_author, "— $author")
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

            // Logo is ALWAYS on (the toggle was removed): watermark + the
            // header wordmark, each in the variant that reads on the card.
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
            // Watermark at ~5% opacity (13/255 ≈ 5.1%) — a faint texture
            // behind the text, not a visible logo.
            views.setInt(R.id.quote_widget_watermark, "setImageAlpha", 13)

            // Tapping the card (outside the buttons) opens the app on the
            // Quote of the day settings screen — the deep link is resolved
            // by Dart at launch; without a live session it falls back to
            // the normal start (the gate decides).
            val openApp = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("enclavdwidget://quote-settings"),
            )
            views.setOnClickPendingIntent(R.id.quote_widget_root, openApp)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /** Dark (default) vs light card: background, text colors, logo glyphs. */
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
        // The stylized marks: brand blue, deeper on light for contrast.
        val markColor =
            if (light) Color.rgb(37, 99, 235) else Color.rgb(59, 130, 246)
        views.setTextColor(R.id.quote_widget_mark, markColor)
        views.setTextColor(R.id.quote_widget_close_mark, markColor)
    }

    /**
     * Sizes scale SEAMLESSLY with the widget width: one continuous scale
     * factor (360dp = 1.0) drives every element — quote, marks, meta,
     * label, action buttons — so a resize scales the whole card
     * proportionally instead of jumping between a few fixed sizes. The
     * quote stays the star; everything else stays small. The wordmark is
     * SMALL and FIXED (label height, never scales) by design.
     */
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

        // Like/dislike buttons scale with the card too.
        views.setViewLayoutWidth(R.id.quote_widget_like, 44f * scale, TypedValue.COMPLEX_UNIT_DIP)
        views.setViewLayoutHeight(R.id.quote_widget_like, 36f * scale, TypedValue.COMPLEX_UNIT_DIP)
        views.setViewLayoutWidth(R.id.quote_widget_dislike, 44f * scale, TypedValue.COMPLEX_UNIT_DIP)
        views.setViewLayoutHeight(R.id.quote_widget_dislike, 36f * scale, TypedValue.COMPLEX_UNIT_DIP)
        views.setTextViewTextSize(R.id.quote_widget_like, TypedValue.COMPLEX_UNIT_SP, actionEmoji)
        views.setTextViewTextSize(R.id.quote_widget_dislike, TypedValue.COMPLEX_UNIT_SP, actionEmoji)

        // Wordmark (1584x231 ≈ 6.86:1): SMALL and FIXED — about the height
        // of the "QUOTE OF THE DAY" label, never scaling with the width.
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
        // Watermark icon — a big centered mark, ~85% of the smaller side
        // (it is a faint 5%-alpha texture, so it can stay generous).
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

        // Narrow card (≈2 cells): no room for label + wordmark — the
        // wordmark overrides the title (the user's rule).
        views.setViewVisibility(
            R.id.quote_widget_label,
            if (widthDp >= 260) View.VISIBLE else View.GONE,
        )
    }

    /** True when the system is in dark (night) mode. */
    private fun isNight(context: Context): Boolean {
        val mode =
            context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return mode == Configuration.UI_MODE_NIGHT_YES
    }

    /**
     * Like/dislike row: unrated → both neutral + wired to the Dart rate
     * callback; rated → the buttons DISAPPEAR and a single emoji of the
     * chosen side (👍 or 👎) marks the vote — visible but not loud, no
     * colored confirmation banner.
     */
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
            // Just the chosen side's emoji — muted like the rest of the
            // meta text (the emoji glyph itself carries the color).
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
        private const val KEY_LIGHT = "widget_light"
        private const val KEY_FOLLOW_SYSTEM = "widget_follow_system"
    }
}
