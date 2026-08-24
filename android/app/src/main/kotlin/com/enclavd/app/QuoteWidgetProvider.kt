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
 * tags / light variant) are ALSO widget data, toggled from the app's
 * Quote of the day settings — every render reads them from the same
 * source.
 *
 * Design ("white-house document"): the logo is ALWAYS on — a large
 * low-opacity watermark of the app icon in the middle of the card with
 * the quote text over it, plus the app header's wordmark at the top
 * right (it takes over the "QUOTE OF THE DAY" title on narrow widgets).
 * The quote renders without wrapping quotation marks; a large blue
 * stylized " mark sits above it instead. After a vote the buttons
 * disappear and a "Liked ✓" / "Disliked ✓" confirmation takes their
 * place — the user always sees what their tap did (and a vote cast on
 * the website shows up here the same way on the next push).
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
        val light = data.getBoolean(KEY_LIGHT, false)

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
                views.setViewVisibility(R.id.quote_widget_author, View.GONE)
                views.setViewVisibility(R.id.quote_widget_tags, View.GONE)
                views.setViewVisibility(R.id.quote_widget_actions, View.GONE)
                views.setViewVisibility(R.id.quote_widget_rated, View.GONE)
            } else {
                // No wrapping quotes — the big blue mark above carries the
                // quotation styling now.
                views.setTextViewText(R.id.quote_widget_text, text)
                views.setTextViewText(R.id.quote_widget_author, "— $author")
                views.setTextViewText(R.id.quote_widget_tags, tagSpans(tags, light))
                views.setViewVisibility(R.id.quote_widget_mark, View.VISIBLE)
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
            // Watermark at ~10% opacity (25/255 ≈ 9.8%).
            views.setInt(R.id.quote_widget_watermark, "setImageAlpha", 25)

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
        // The stylized mark: brand blue, deeper on light for contrast.
        views.setTextColor(
            R.id.quote_widget_mark,
            if (light) Color.rgb(37, 99, 235) else Color.rgb(59, 130, 246),
        )
    }

    /**
     * Sizes scale with the widget width. The QUOTE is the star: it grows
     * aggressively (17sp at min → 30sp on large) so it stays the first
     * thing the eye lands on; everything else stays small. The blue mark
     * is always ~1.5× the quote. The wordmark and watermark grow with
     * the widget too.
     */
    private fun applySizes(views: RemoteViews, widthDp: Int, heightDp: Int) {
        val (text, mark, author, tags, label) = when {
            widthDp >= 500 -> Sizes(30f, 46f, 14f, 13f, 11f)
            widthDp >= 360 -> Sizes(24f, 37f, 13f, 12f, 11f)
            widthDp >= 280 -> Sizes(20f, 31f, 12f, 11f, 10f)
            else -> Sizes(17f, 26f, 11f, 10f, 10f)
        }
        views.setTextViewTextSize(R.id.quote_widget_text, TypedValue.COMPLEX_UNIT_SP, text)
        views.setTextViewTextSize(R.id.quote_widget_mark, TypedValue.COMPLEX_UNIT_SP, mark)
        views.setTextViewTextSize(R.id.quote_widget_author, TypedValue.COMPLEX_UNIT_SP, author)
        views.setTextViewTextSize(R.id.quote_widget_tags, TypedValue.COMPLEX_UNIT_SP, tags)
        views.setTextViewTextSize(R.id.quote_widget_label, TypedValue.COMPLEX_UNIT_SP, label)
        views.setTextViewTextSize(R.id.quote_widget_rated, TypedValue.COMPLEX_UNIT_SP, author)

        // Wordmark (1584x231 ≈ 6.86:1) — up to ~40% of the widget width;
        // on narrow widgets the "QUOTE OF THE DAY" title gives way to it.
        val wordmarkWidthDp = (widthDp * 0.4f).coerceIn(48f, 180f)
        val wordmarkHeightDp = wordmarkWidthDp * 231f / 1584f
        views.setViewLayoutParams(
            R.id.quote_widget_wordmark,
            RemoteViews.LayoutParams(
                dp(context, wordmarkWidthDp),
                dp(context, wordmarkHeightDp),
            ),
        )
        // Watermark icon — a big centered mark, ~85% of the smaller side.
        val watermarkDp = (minOf(widthDp, heightDp) * 0.85f).coerceIn(48f, 260f)
        views.setViewLayoutParams(
            R.id.quote_widget_watermark,
            RemoteViews.LayoutParams(
                dp(context, watermarkDp),
                dp(context, watermarkDp),
            ),
        )

        // Narrow card (≈2 cells): no room for label + wordmark — the
        // wordmark overrides the title (the user's rule).
        views.setViewVisibility(
            R.id.quote_widget_label,
            if (widthDp >= 260) View.VISIBLE else View.GONE,
        )
    }

    private fun dp(context: Context, valueDp: Float): Int =
        (valueDp * context.resources.displayMetrics.density).toInt()

    private data class Sizes(
        val text: Float,
        val mark: Float,
        val author: Float,
        val tags: Float,
        val label: Float,
    )

    /**
     * Like/dislike row: unrated → both neutral + wired to the Dart rate
     * callback; rated → the buttons DISAPPEAR and a small confirmation
     * ("Liked ✓" / "Disliked ✓") takes their place — the vote feedback.
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
            if (rated == "like") {
                views.setTextViewText(R.id.quote_widget_rated, "✓ Liked")
                views.setTextColor(
                    R.id.quote_widget_rated,
                    if (light) Color.rgb(22, 163, 74) else Color.rgb(74, 222, 128),
                )
            } else {
                views.setTextViewText(R.id.quote_widget_rated, "✓ Disliked")
                views.setTextColor(
                    R.id.quote_widget_rated,
                    if (light) Color.rgb(220, 38, 38) else Color.rgb(248, 113, 113),
                )
            }
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
    }
}
