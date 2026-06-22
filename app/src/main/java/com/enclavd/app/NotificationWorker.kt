package com.enclavd.app

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class NotificationWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(context, workerParams) {

    override suspend fun doWork(): Result {
        return try {
            // Get session cookies
            val cookieManager = android.webkit.CookieManager.getInstance()
            val cookies = cookieManager.getCookie("https://enclavd.com")
            
            if (cookies == null) {
                Log.d("NotificationWorker", "No cookies found, skipping notification check.")
                return Result.success()
            }

            val url = URL("https://enclavd.com/handlers/notifications/get_notifications.php")
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.setRequestProperty("Cookie", cookies)
            connection.connect()

            if (connection.responseCode == HttpURLConnection.HTTP_OK) {
                val response = connection.inputStream.bufferedReader().use { it.readText() }
                val jsonObject = JSONObject(response)
                
                if (jsonObject.has("notifications")) {
                    val notificationsArray = jsonObject.getJSONArray("notifications")
                    
                    val sharedPrefs = context.getSharedPreferences("enclavd_prefs", Context.MODE_PRIVATE)
                    val lastSeenId = sharedPrefs.getInt("last_notification_id", 0)
                    var maxId = lastSeenId
                    
                    for (i in 0 until notificationsArray.length()) {
                        val notif = notificationsArray.getJSONObject(i)
                        val id = notif.getInt("id")
                        
                        if (id > lastSeenId) {
                            maxId = maxOf(maxId, id)
                            val message = notif.getString("message")
                            showNotification(id, message)
                        }
                    }
                    
                    if (maxId > lastSeenId) {
                        sharedPrefs.edit().putInt("last_notification_id", maxId).apply()
                    }
                }
            }
            Result.success()
        } catch (e: Exception) {
            e.printStackTrace()
            Result.retry()
        }
    }

    private fun showNotification(id: Int, message: String) {
        // Ensure permission is granted (for Android 13+)
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return
        }

        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            context, id, intent, PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, "enclavd_notifications")
            .setSmallIcon(R.drawable.logo)
            .setContentTitle("Enclavd")
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        with(NotificationManagerCompat.from(context)) {
            notify(id, builder.build())
        }
    }
}
