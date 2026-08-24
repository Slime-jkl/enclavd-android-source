package com.enclavd.app

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * Re-renders the daily-quote widget when the system configuration changes
 * (notably light/dark theme flips, but also rotation/locale/font scale).
 *
 * The widget follows the SYSTEM theme by default, so it must repaint when
 * the theme flips. CONFIGURATION_CHANGED is an implicit broadcast — it
 * CANNOT be manifest-registered on API 26+ — so MainActivity registers
 * this receiver on the Context while the process lives (and also renders
 * once on create, covering a theme flip that happened while the app was
 * dead). The render is cheap: RemoteViews from already-pushed widget
 * data, no network.
 */
class QuoteWidgetConfigReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_CONFIGURATION_CHANGED) return
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, QuoteWidgetProvider::class.java),
        )
        if (ids.isEmpty()) return
        QuoteWidgetProvider().render(
            context,
            manager,
            ids,
            HomeWidgetPlugin.getData(context),
        )
    }
}
