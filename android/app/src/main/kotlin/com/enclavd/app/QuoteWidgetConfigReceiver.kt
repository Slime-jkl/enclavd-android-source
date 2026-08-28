package com.enclavd.app

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import es.antonborri.home_widget.HomeWidgetPlugin

/** Re-renders the quote widget on system config changes (theme flips). */
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
