package com.enclavd.app

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val KEEP_ALIVE_CHANNEL = "enclavd/keepalive"
        const val PREFS_NAME = "enclavd_keepalive"
        const val PREFS_ENABLED = "enabled"
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
    override fun onStop() {
        super.onStop()
        if (keepAliveEnabled()) {
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
