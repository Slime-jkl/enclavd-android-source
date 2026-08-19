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
import androidx.core.app.RemoteInput
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

    /**
     * GET a JSON api/v1 endpoint with the session cookie and the pinned UA
     * (see AppConstants.USER_AGENT — the server agent-binds sessions).
     * Returns null on transport errors or non-200 (auth gone, server trouble).
     */
    private fun apiGet(urlStr: String, cookies: String): JSONObject? {
        return try {
            val connection = URL(urlStr).openConnection() as HttpURLConnection
            connection.requestMethod = "GET"
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            connection.setRequestProperty("User-Agent", AppConstants.USER_AGENT)
            connection.setRequestProperty("Cookie", cookies)
            connection.connect()
            if (connection.responseCode == HttpURLConnection.HTTP_OK) {
                JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
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

            /* ── Notifications (likes / comments / mentions / follows) ── */
            val jsonObject = apiGet(AppConstants.NOTIFICATIONS_API, cookies)
            if (jsonObject != null) {
                // CSRF token for notification quick replies — the api/v1 list
                // response exposes the session's token so the worker can POST.
                val csrf = jsonObject.optString("csrf_token", "")
                if (csrf.isNotEmpty()) {
                    sharedPrefs.edit().putString("csrf_token", csrf).apply()
                }

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

            /* ── Messages (unread, with quick reply) ── */
            val messagesJson = apiGet(AppConstants.MESSAGES_API, cookies)
            if (messagesJson != null && messagesJson.has("messages")) {
                val messagesArray = messagesJson.getJSONArray("messages")
                val shownMsgKeys = sharedPrefs
                    .getStringSet("shown_message_keys", emptySet())
                    ?.toMutableSet() ?: mutableSetOf()

                for (i in 0 until messagesArray.length()) {
                    val msg = messagesArray.getJSONObject(i)
                    val messageId = msg.getInt("message_id")
                    // Unread messages stay unread until read in-app or replied
                    // to, so dedupe by message id to avoid re-firing the same
                    // notification every worker run.
                    val key = "msg:$messageId"
                    if (shownMsgKeys.contains(key)) continue
                    shownMsgKeys.add(key)

                    val conversationId = msg.getInt("conversation_id")
                    val senderName = msg.optString("sender_name", "Enclavd")
                    val text = msg.optString("message", "")
                    val rawAvatar = msg.optString("sender_avatar", "")
                    val avatarUrl = if (rawAvatar.startsWith("/")) "https://enclavd.com$rawAvatar" else rawAvatar
                    val avatarBitmap = if (avatarUrl.isNotEmpty() && avatarUrl != "null") downloadBitmap(avatarUrl) else null
                    val csrf = sharedPrefs.getString("csrf_token", "") ?: ""

                    showMessageNotification(messageId, conversationId, senderName, text, avatarBitmap, cookies, csrf)
                }

                if (shownMsgKeys.isNotEmpty()) {
                    sharedPrefs.edit()
                        .putStringSet("shown_message_keys", pruneShownKeys(shownMsgKeys))
                        .apply()
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

    /**
     * Show a "New message from X" notification with a quick-reply action.
     * Tapping the notification deep-links into the conversation; replying
     * hands off to MessageReplyReceiver, which posts through api/v1.
     */
    private fun showMessageNotification(
        messageId: Int,
        conversationId: Int,
        senderName: String,
        message: String,
        avatarBitmap: Bitmap?,
        cookies: String,
        csrf: String
    ) {
        // Ensure permission is granted (for Android 13+)
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return
        }

        val notificationId = AppConstants.MESSAGE_NOTIFICATION_OFFSET + messageId

        // Tap → open the conversation in the WebView.
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("url", "${AppConstants.SITE_URL}/messages?conversation=$conversationId")
        }
        val openPendingIntent = PendingIntent.getActivity(
            context, messageId, openIntent, PendingIntent.FLAG_IMMUTABLE
        )

        // Reply → MessageReplyReceiver posts through api/v1/messages.
        val replyIntent = Intent(context, MessageReplyReceiver::class.java).apply {
            putExtra(MessageReplyReceiver.EXTRA_CONVERSATION_ID, conversationId)
            putExtra(MessageReplyReceiver.EXTRA_COOKIE, cookies)
            putExtra(MessageReplyReceiver.EXTRA_CSRF, csrf)
            putExtra(MessageReplyReceiver.EXTRA_NOTIFICATION_ID, notificationId)
        }
        val replyPendingIntent = PendingIntent.getBroadcast(
            context,
            messageId,
            replyIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val replyAction = NotificationCompat.Action.Builder(
            R.drawable.ic_notification,
            "Reply",
            replyPendingIntent
        ).addRemoteInput(
            RemoteInput.Builder(MessageReplyReceiver.EXTRA_REPLY)
                .setLabel("Reply")
                .build()
        ).build()

        val builder = NotificationCompat.Builder(context, "enclavd_notifications")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("New message from $senderName")
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(openPendingIntent)
            .addAction(replyAction)
            .setAutoCancel(true)

        if (avatarBitmap != null) {
            builder.setLargeIcon(avatarBitmap)
        }

        with(NotificationManagerCompat.from(context)) {
            notify(notificationId, builder.build())
        }
    }
}
