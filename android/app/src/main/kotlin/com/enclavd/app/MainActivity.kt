package com.enclavd.app

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import es.antonborri.home_widget.HomeWidgetPlugin

class MainActivity : FlutterActivity() {

    private companion object {
        const val KEEP_ALIVE_CHANNEL = "enclavd/keepalive"
        const val PREFS_NAME = "enclavd_keepalive"
        const val PREFS_ENABLED = "enabled"
    }

    // Re-renders the widget on theme flips. CONFIGURATION_CHANGED is implicit,
    // so the receiver is context-registered; unregistered in onDestroy.
    private var configReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Repaint now: the theme may have flipped while the app was dead.
        renderQuoteWidget()
        val receiver = QuoteWidgetConfigReceiver()
        val filter = IntentFilter(Intent.ACTION_CONFIGURATION_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        configReceiver = receiver
    }

    private fun renderQuoteWidget() {
        val manager = AppWidgetManager.getInstance(this)
        val ids = manager.getAppWidgetIds(
            ComponentName(this, QuoteWidgetProvider::class.java),
        )
        if (ids.isEmpty()) return
        QuoteWidgetProvider().render(
            this,
            manager,
            ids,
            HomeWidgetPlugin.getData(this),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            KEEP_ALIVE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(keepAliveEnabled())
                "setEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setKeepAliveEnabled(enabled)
                    if (!enabled) {
                        stopService(Intent(this, RealtimeKeepAliveService::class.java))
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Hold the process perceptible while minimized so the realtime streams
    // keep their network; skipped when a push transport is active.
    override fun onStop() {
        super.onStop()
        val pushActive = getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        ).getBoolean("flutter.push_transport_active", false)
        if (keepAliveEnabled() && !pushActive) {
            val intent = Intent(this, RealtimeKeepAliveService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        }
    }

    // Foreground again: streams are live, drop the keep-alive.
    override fun onStart() {
        super.onStart()
        stopService(Intent(this, RealtimeKeepAliveService::class.java))
    }

    override fun onDestroy() {
        configReceiver?.let { unregisterReceiver(it) }
        configReceiver = null
        stopService(Intent(this, RealtimeKeepAliveService::class.java))
        super.onDestroy()
    }

    private fun keepAlivePrefs(): SharedPreferences =
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun keepAliveEnabled(): Boolean =
        keepAlivePrefs().getBoolean(PREFS_ENABLED, true)

    private fun setKeepAliveEnabled(enabled: Boolean) {
        keepAlivePrefs().edit().putBoolean(PREFS_ENABLED, enabled).apply()
    }
}
