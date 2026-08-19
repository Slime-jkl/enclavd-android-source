package com.enclavd.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Handles the quick-reply action on message notifications. Receives the
 * typed reply via RemoteInput, then POSTs it to api/v1/messages with the
 * stored session cookie and CSRF token (both captured when the notification
 * was built), and dismisses the notification on success.
 */
class MessageReplyReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val replyText = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(EXTRA_REPLY)
            ?.toString()
            ?.trim()
            ?: return
        val conversationId = intent.getIntExtra(EXTRA_CONVERSATION_ID, -1)
        val cookies = intent.getStringExtra(EXTRA_COOKIE) ?: return
        val csrf = intent.getStringExtra(EXTRA_CSRF) ?: return
        if (conversationId <= 0 || replyText.isEmpty()) return

        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        val pendingResult = goAsync()
        Thread {
            try {
                val connection = URL("${AppConstants.SITE_URL}/api/v1/messages")
                    .openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.connectTimeout = 15000
                connection.readTimeout = 15000
                connection.doOutput = true
                connection.setRequestProperty("User-Agent", AppConstants.USER_AGENT)
                connection.setRequestProperty("Cookie", cookies)
                connection.setRequestProperty("X-CSRF-Token", csrf)
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")

                val body = JSONObject()
                    .put("action", "reply")
                    .put("conversation_id", conversationId)
                    .put("message", replyText)
                    .toString()
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

                if (connection.responseCode == HttpURLConnection.HTTP_OK && notificationId > 0) {
                    // Sent — dismiss the message notification.
                    NotificationManagerCompat.from(context).cancel(notificationId)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    companion object {
        const val EXTRA_REPLY = "reply_text"
        const val EXTRA_CONVERSATION_ID = "conversation_id"
        const val EXTRA_COOKIE = "cookie"
        const val EXTRA_CSRF = "csrf"
        const val EXTRA_NOTIFICATION_ID = "notification_id"
    }
}
