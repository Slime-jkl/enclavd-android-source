package com.enclavd.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground-service keep-alive for the realtime streams.
 *
 * When the app goes to the background, Android suspends network access for
 * backgrounded apps (Doze / app standby / background-data restrictions):
 * the live SSE + WS sockets die and every reconnect fails with a socket
 * error until the app returns to the foreground (seen on-device as the
 * "sse stream ended / sse socket error" loop in logcat while minimized).
 * A foreground service holds the process in the "perceptible" state, which
 * exempts it from those network restrictions — so the Flutter isolate's
 * streams keep delivering while minimized.
 *
 * The service itself does NO work: no engine, no timer, no sockets. It only
 * exists so the process stays perceptible while backgrounded. MainActivity
 * starts it in onStop() and stops it in onStart(); the notification is low
 * importance on its own channel (no sound/vibration/badge) and can be
 * hidden in OS settings without stopping the service.
 */
class RealtimeKeepAliveService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        // START_STICKY: if the system ever has to reclaim the process, the
        // service restarts (and re-creates the notification) once the
        // process is back — the streams reconnect on their own backoff.
        return START_STICKY
    }

    private fun startForegroundCompat() {
        val channelId = "keepalive"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Background live updates",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description =
                        "Keeps notifications and messages live while Enclavd is minimized"
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                }
            )
        }

        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        val notification: Notification = builder
            .setSmallIcon(R.drawable.ic_stat_enclavd)
            .setContentTitle("Enclavd")
            .setContentText("Live updates active")
            .setContentIntent(pending)
            .setOngoing(true)
            .setPriority(Notification.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    companion object {
        private const val NOTIFICATION_ID = 0xEA71 // "keepalive" id space
    }
}
