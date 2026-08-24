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

    // Live re-render of the daily-quote widget on system theme flips
    // (context-registered — CONFIGURATION_CHANGED is implicit and cannot
    // be manifest-registered on API 26+). Unregistered in onDestroy.
    private var configReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The widget follows the system light/dark theme: repaint it now
        // (a theme may have flipped while the app was dead) and register
        // so future flips repaint it live while this process lives.
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

    // The activity is no longer visible — hold the process perceptible so
    // the Dart realtime streams keep their network while minimized.
    // Conditional fallback: with a push transport active (FCM / Unified
    // Push), background delivery is the push service's job — the keep-alive
    // FGS is unnecessary and its persistent notice is noise. Dart writes
    // the flag in PushManager; the Flutter SharedPreferences live in the
    // native "FlutterSharedPreferences" file under the "flutter." prefix.
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

    // Back in the foreground: the streams are live again, drop the keep-alive.
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
