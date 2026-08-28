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

/** Foreground-service keep-alive: keeps the process perceptible while minimized. */
class RealtimeKeepAliveService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        // START_STICKY: restart if the system reclaims the process.
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
