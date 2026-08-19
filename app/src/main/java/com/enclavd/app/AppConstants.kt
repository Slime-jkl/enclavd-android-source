package com.enclavd.app

/**
 * App-wide constants shared between the UI process (MainActivity) and the
 * background worker process (NotificationWorker).
 */
object AppConstants {

    const val SITE_URL = "https://enclavd.com"

    /**
     * The exact User-Agent the WebView is pinned to (see MainActivity).
     *
     * The server binds every login session to the agent string that was
     * sent at login time (SessionManager agent binding), so the background
     * worker MUST send this identical string. Sending the platform default
     * Java UA makes the server treat the worker as a different client: it
     * rejects the request and revokes the session row — the root cause of
     * "notifications don't work when the app is closed".
     */
    const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

    /** api/v1 notifications list endpoint (bundled, newest 5). */
    const val NOTIFICATIONS_API = "https://enclavd.com/api/v1/notifications?list=1"
}
