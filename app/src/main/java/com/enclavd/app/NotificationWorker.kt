package com.enclavd.app

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
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

    private fun downloadBitmap(urlStr: String): Bitmap? {
        return try {
            val url = URL(urlStr)
            val connection = url.openConnection() as HttpURLConnection
            connection.doInput = true
            // Keep the same agent as the session so CDNs/avatars behave
            // identically to the in-app requests.
            connection.setRequestProperty("User-Agent", AppConstants.USER_AGENT)
            connection.connect()
            if (connection.responseCode == HttpURLConnection.HTTP_OK) {
                BitmapFactory.decodeStream(connection.inputStream)
            } else {
                null
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    override suspend fun doWork(): Result {
        return try {
            // Read the session cookie persisted by MainActivity when the WebView
            // was last active. CookieManager.getInstance() is not usable from a
            // background WorkManager process because the WebView process is not
            // running, so it always returns null and the worker exits early.
            val sharedPrefs = context.getSharedPreferences("enclavd_prefs", Context.MODE_PRIVATE)
            val cookies = sharedPrefs.getString("session_cookie", null)

            if (cookies == null) {
                Log.d("NotificationWorker", "No session cookie in SharedPreferences, skipping.")
                return Result.success()
            }

            val url = URL(AppConstants.NOTIFICATIONS_API)
            val connection = url.openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            // CRITICAL: the server binds each login session to the User-Agent
            // seen at login (the WebView's pinned Chrome UA). Sending the
            // platform-default Java UA here made the server treat the worker
            // as a different client: it rejected the request AND revoked the
            // session row, so notifications never arrived while the app was
            // closed and the user was logged out on the next launch.
            connection.setRequestProperty("User-Agent", AppConstants.USER_AGENT)
            connection.setRequestProperty("Cookie", cookies)
            connection.connect()

            if (connection.responseCode == HttpURLConnection.HTTP_OK) {
                val response = connection.inputStream.bufferedReader().use { it.readText() }
                val jsonObject = JSONObject(response)

                if (jsonObject.has("notifications")) {
                    val notificationsArray = jsonObject.getJSONArray("notifications")

                    val lastSeenId = sharedPrefs.getInt("last_notification_id", 0)
                    val shownKeys = sharedPrefs
                        .getStringSet("shown_notification_keys", emptySet())
                        ?.toMutableSet() ?: mutableSetOf()
                    var maxId = lastSeenId

                    for (i in 0 until notificationsArray.length()) {
                        val notif = notificationsArray.getJSONObject(i)
                        val id = notif.getInt("id")

                        // Only show notifications that are:
                        //   1. newer than the last one we already showed, AND
                        //   2. unread on the server side ("read": false)
                        // This prevents already-read notifications from being
                        // re-fired on every worker run.
                        val isRead = notif.optBoolean("read", true)
                        if (id <= lastSeenId || isRead) continue

                        // Bundle re-fires: the api/v1 list bundles likes and
                        // comments per post ("Alice & 3 others liked your
                        // post"), so a NEW like on a post we already pushed
                        // arrives with a NEW id but the SAME (type, post) key.
                        // Without this guard the same message would re-fire on
                        // every worker run — the duplicate notifications bug.
                        val contentType = notif.optString("content_type", "")
                        val contentId = notif.optString("content_id", "")
                        val key = if (
                            contentType == "post-like" ||
                            contentType == "post-comment" ||
                            contentType == "comment-mention"
                        ) {
                            "$contentType:$contentId"
                        } else {
                            "$contentType:$id"
                        }
                        if (shownKeys.contains(key)) continue
                        shownKeys.add(key)

                        maxId = maxOf(maxId, id)
                        val message = notif.getString("message")

                        val rawAvatar = notif.optString("from_user_avatar", "")
                        val avatarUrl = if (rawAvatar.startsWith("/")) "https://enclavd.com$rawAvatar" else rawAvatar
                        val avatarBitmap = if (avatarUrl.isNotEmpty() && avatarUrl != "null") downloadBitmap(avatarUrl) else null

                        var postImageBitmap: Bitmap? = null
                        if (notif.has("post_preview") && !notif.isNull("post_preview")) {
                            val postPreview = notif.getJSONObject("post_preview")
                            val rawPostImage = postPreview.optString("image_url", "")
                            // The api/v1 list serves gallery images as bare
                            // filenames ("abc.jpg") — they live under
                            // /public/gallery/ on the site. Absolute paths
                            // (avatars, /assets/...) are used as-is.
                            val postImageUrl = when {
                                rawPostImage.isEmpty() || rawPostImage == "null" -> ""
                                rawPostImage.startsWith("http") -> rawPostImage
                                rawPostImage.startsWith("/") -> "https://enclavd.com$rawPostImage"
                                else -> "https://enclavd.com/public/gallery/$rawPostImage"
                            }
                            if (postImageUrl.isNotEmpty()) {
                                postImageBitmap = downloadBitmap(postImageUrl)
                            }
                        }

                        showNotification(id, message, avatarBitmap, postImageBitmap)
                    }

                    if (maxId > lastSeenId || shownKeys.isNotEmpty()) {
                        sharedPrefs.edit()
                            .putInt("last_notification_id", maxId)
                            .putStringSet("shown_notification_keys", pruneShownKeys(shownKeys))
                            .apply()
                    }
                }
            }
            // Non-200 (401/403 = session gone, 5xx = server trouble): skip this
            // run quietly. The session may come back after the user logs in
            // again — the stored cookie is updated on the next page load.
            Result.success()
        } catch (e: Exception) {
            e.printStackTrace()
            Result.retry()
        }
    }

    /**
     * Keep the shown-key set bounded. Order is not guaranteed by
     * SharedPreferences, so when it outgrows the cap we drop the first
     * entries arbitrarily — the worst case is a single re-fire.
     */
    private fun pruneShownKeys(keys: Set<String>): Set<String> {
        if (keys.size <= 200) return keys
        return keys.drop(100).toSet()
    }

    private fun showNotification(id: Int, message: String, avatarBitmap: Bitmap?, postImageBitmap: Bitmap?) {
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
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Enclavd")
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        if (avatarBitmap != null) {
            builder.setLargeIcon(avatarBitmap)
        }

        if (postImageBitmap != null) {
            builder.setStyle(NotificationCompat.BigPictureStyle()
                .bigPicture(postImageBitmap)
                .bigLargeIcon(null as Bitmap?) // hides large icon when expanded
            )
        }

        with(NotificationManagerCompat.from(context)) {
            notify(id, builder.build())
        }
    }
}
