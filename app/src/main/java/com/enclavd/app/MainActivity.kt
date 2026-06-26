package com.enclavd.app

import android.annotation.SuppressLint
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.view.View
import android.view.ViewGroup
import android.webkit.URLUtil
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.RelativeLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import com.google.android.material.bottomsheet.BottomSheetDialog
import android.content.ContentValues
import android.provider.MediaStore
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit
import android.view.WindowManager
import androidx.core.view.WindowCompat

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var layoutError: RelativeLayout
    private lateinit var btnRetry: Button
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private var isError = false
    private var hasLoadedOnce = false
	private lateinit var splashOverlay: RelativeLayout

    private var uploadMessage: ValueCallback<Array<Uri>>? = null

    private val fileChooserLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (uploadMessage == null) return@registerForActivityResult
        val data: Intent? = result.data
        val resultUriArray = WebChromeClient.FileChooserParams.parseResult(result.resultCode, data)
        uploadMessage?.onReceiveValue(resultUriArray)
        uploadMessage = null
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
		val splashScreen = installSplashScreen()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val window = this.window
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.statusBarColor = android.graphics.Color.parseColor("#FF0A1120")
        window.navigationBarColor = android.graphics.Color.parseColor("#FF0A1120")
        
        val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
        windowInsetsController.isAppearanceLightStatusBars = false
        windowInsetsController.isAppearanceLightNavigationBars = false

        webView = findViewById(R.id.webView)
        layoutError = findViewById(R.id.layoutError)
        btnRetry = findViewById(R.id.btnRetry)
        swipeRefresh = findViewById(R.id.swipeRefresh)
		splashOverlay = findViewById(R.id.splashOverlay)

        createNotificationChannel()
        requestNotificationPermission()
        scheduleNotificationWorker()

        // Web State Engine Settings
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.databaseEnabled = true
        webView.settings.loadsImagesAutomatically = true
        webView.settings.allowFileAccess = true
        // Required so that onCreateWindow fires for window.open / popup targets
        // (e.g. YouTube sign-in, "Watch on YouTube" links inside iframes).
        webView.settings.setSupportMultipleWindows(true)
        // Spoof a modern Chrome for Android User-Agent so YouTube and other
        // third-party embeds serve the real player/content instead of fallbacks
        // or bot-verification gates. The UA is pinned to a stable Chrome release
        // to avoid triggering platform-detection mismatches.
        webView.settings.userAgentString =
            "Mozilla/5.0 (Linux; Android 10; K) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/124.0.0.0 Mobile Safari/537.36"

        // Persistent Cookie Storage Architecture
        val cookieManager = android.webkit.CookieManager.getInstance()
        cookieManager.setAcceptCookie(true)
        cookieManager.setAcceptThirdPartyCookies(webView, true) 
        android.webkit.WebViewDatabase.getInstance(this)
        cookieManager.flush()

        // Material UI Long Press Image Detector
        webView.setOnLongClickListener {
            val hitTestResult = webView.hitTestResult
            if (hitTestResult.type == WebView.HitTestResult.IMAGE_TYPE || 
                hitTestResult.type == WebView.HitTestResult.SRC_IMAGE_ANCHOR_TYPE) {
                
                val imageUrl = hitTestResult.extra
                if (imageUrl != null) {
                    showMaterialBottomSheet(imageUrl)
                }
                true
            } else {
                false
            }
        }

        webView.webChromeClient = object : WebChromeClient() {

            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                if (uploadMessage != null) {
                    uploadMessage?.onReceiveValue(null)
                    uploadMessage = null
                }
                uploadMessage = filePathCallback
                val intent = fileChooserParams?.createIntent()
                try {
                    if (intent != null) fileChooserLauncher.launch(intent)
                } catch (e: ActivityNotFoundException) {
                    uploadMessage = null
                    return false
                }
                return true
            }

            // Intercept window.open() / popup navigations triggered by iframe content
            // (e.g. "Watch on YouTube", "Sign In" inside YouTube embeds).
            //
            // Gate strictly on isUserGesture:
            //   • true  → the user deliberately tapped something that opens a new window.
            //             Extract the target URL and hand it to the system browser so
            //             the user gets a full browser experience. The main WebView is
            //             left completely unchanged.
            //   • false → background / programmatic window.open (preloaders, ad iframes,
            //             analytics). Silently discard by returning false so the WebView
            //             engine cleans up without creating any visible state.
            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: android.os.Message?
            ): Boolean {
                // Suppress all non-gesture popups immediately — nothing to do.
                if (!isUserGesture) return false

                // For user-initiated popups, try the fast path first:
                // hitTestResult.extra already contains the tapped URL.
                val targetUrl = view?.hitTestResult?.extra
                if (!targetUrl.isNullOrBlank()) {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(targetUrl)))
                    } catch (e: ActivityNotFoundException) { /* no handler — silently drop */ }
                    return true
                }

                // Fallback: the URL isn't available on the hit-test result yet
                // (some YouTube links resolve it asynchronously). Spin up a minimal
                // ephemeral WebView wired to the transport so the engine can deliver
                // the URL, then intercept it, fire the system browser, and destroy
                // the temp view immediately. The main WebView is never affected.
                val tempWebView = WebView(this@MainActivity)
                tempWebView.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(
                        v: WebView?,
                        req: WebResourceRequest?
                    ): Boolean {
                        val url = req?.url?.toString() ?: return false
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        } catch (e: ActivityNotFoundException) { /* no handler */ }
                        tempWebView.destroy()
                        return true
                    }
                }
                val transport = resultMsg?.obj as? WebView.WebViewTransport
                transport?.webView = tempWebView
                resultMsg?.sendToTarget()
                return true
            }
        }

        webView.setDownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
            triggerStandardDownload(url, userAgent, contentDisposition, mimeType)
        }

        webView.webViewClient = object : WebViewClient() {

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url?.toString() ?: return false
                val host = Uri.parse(url).host ?: ""

                // 1. Enclavd content always loads inside the WebView.
                if (host.endsWith("enclavd.com")) return false

                // 2. Embed infrastructure allowlist — always stay in WebView, regardless
                //    of gesture. These domains are YouTube's internal ad and player
                //    machinery. When a user taps Play, the gesture propagates to ad-ping
                //    requests on these domains, causing hasGesture() to return true even
                //    though the user never intended to navigate anywhere. Sending them to
                //    the system browser would open a raw tracking URL or crash with no
                //    handler. They must always load silently inside the WebView.
                val embedInfrastructure = arrayOf(
                    "doubleclick.net",        // Google / YouTube ad serving
                    "googlesyndication.com",  // Google ad syndication
                    "googleadservices.com",   // Google ad services
                    "google-analytics.com",   // Analytics pings
                    "googletagmanager.com",   // Tag manager
                    "googleapis.com",         // YouTube player API calls
                    "ggpht.com",              // YouTube/Google image CDN
                    "ytimg.com",              // YouTube image/script CDN
                    "youtube.com",            // YouTube player & embed requests
                    "youtu.be"                // YouTube short-link redirects
                )
                if (embedInfrastructure.any { host == it || host.endsWith(".$it") }) return false

                // 3. User-initiated navigation (tap, keyboard) on any non-infrastructure
                //    external domain → hand off to the system browser.
                //    This covers article links, channel pages opened deliberately, etc.
                if (request.hasGesture()) {
                    return try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        true
                    } catch (e: ActivityNotFoundException) {
                        false
                    }
                }

                // 4. Background / programmatic request with no user gesture
                //    (iframe src loads, scripts, thumbnail fetches, API calls, etc.)
                //    → allow inside the WebView so embeds work.
                return false
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                // onPageStarted fires only for main-frame navigations; safe to
                // unconditionally reset the error flag here.
                isError = false
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                super.onReceivedError(view, request, error)
                // Sub-resource failures (YouTube CDN, img.youtube.com, etc.) must
                // never trigger the error screen or dismiss the splash. Only a
                // failure on the main enclavd.com frame is treated as fatal.
                if (request?.isForMainFrame == true) {
                    isError = true
                    showErrorScreen()
                    swipeRefresh.isRefreshing = false
                    splashOverlay.visibility = View.GONE
                }
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                // onPageFinished fires for every completed frame load, including
                // YouTube iframes. Guard on enclavd.com so the splash is dismissed
                // exactly once — when the Enclavd page itself is ready.
                val host = Uri.parse(url).host ?: ""
                if (host.endsWith("enclavd.com")) {
                    swipeRefresh.isRefreshing = false
                    splashOverlay.visibility = View.GONE
                    if (!isError) {
                        showWebView()
                        hasLoadedOnce = true

                        // Persist the current session cookie so NotificationWorker
                        // can authenticate while running in the background (the
                        // WebView CookieManager is not available in background
                        // worker processes).
                        val cookieManager = android.webkit.CookieManager.getInstance()
                        val cookie = cookieManager.getCookie("https://enclavd.com")
                        if (!cookie.isNullOrEmpty()) {
                            getSharedPreferences("enclavd_prefs", Context.MODE_PRIVATE)
                                .edit()
                                .putString("session_cookie", cookie)
                                .apply()
                        }
                    }
                }
            }
        }

        val url = getString(R.string.website_url)
        webView.loadUrl(url)

        btnRetry.setOnClickListener {
            webView.reload()
        }

        // FIXED: Cache clearing logic removed to protect active cookies and login sessions
        swipeRefresh.setOnRefreshListener {
            webView.reload()
        }
    }

    // Material 3 Dark Themed Bottom Sheet Layout
    private fun showMaterialBottomSheet(imageUrl: String) {
        val bottomSheetDialog = BottomSheetDialog(this)
        val context = this
		
        val linearLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setPadding(0, 48, 0, 64)
			
            val shape = android.graphics.drawable.GradientDrawable().apply {
                setColor(android.graphics.Color.parseColor("#111827")) // Tailwind bg-gray-900
                cornerRadii = floatArrayOf(40f, 40f, 40f, 40f, 0f, 0f, 0f, 0f)
            }
            background = shape
        }

        // Drag Handle (Tailwind gray-700)
        val dragHandle = View(context).apply {
            layoutParams = LinearLayout.LayoutParams(96, 12).apply {
                gravity = android.view.Gravity.CENTER_HORIZONTAL
                setMargins(0, 0, 0, 48)
            }
            val handleShape = android.graphics.drawable.GradientDrawable().apply {
                setColor(android.graphics.Color.parseColor("#374151"))
                cornerRadius = 6f
            }
            background = handleShape
        }
        linearLayout.addView(dragHandle)

        // Header Title (Tailwind gray-400)
        val title = TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            text = "Image Options"
            textSize = 14f
            typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            setPadding(0, 0, 0, 32)
            setTextColor(android.graphics.Color.parseColor("#9CA3AF"))
        }
        linearLayout.addView(title)

        // Action Row Button (Tailwind text-gray-50)
        val saveOption = TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            text = "Save Image to Gallery"
            textSize = 16f
            typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
            setPadding(64, 40, 64, 40)
            setTextColor(android.graphics.Color.parseColor("#F9FAFB"))
			
            val drawable = androidx.core.content.ContextCompat.getDrawable(context, android.R.drawable.ic_menu_gallery)?.apply {
                setTint(android.graphics.Color.parseColor("#F9FAFB"))
                setBounds(0, 0, 64, 64)
            }
            setCompoundDrawables(drawable, null, null, null)
            compoundDrawablePadding = 32

            val outValue = android.util.TypedValue()
            context.theme.resolveAttribute(android.R.attr.selectableItemBackground, outValue, true)
            setBackgroundResource(outValue.resourceId)
            isClickable = true
            isFocusable = true

            setOnClickListener {
                saveImageToDCIM(imageUrl)
                bottomSheetDialog.dismiss()
            }
        }
        linearLayout.addView(saveOption)

        bottomSheetDialog.setContentView(linearLayout)
		
        // FIXED: Transparent mask applied directly onto the platform content view holder shell
        bottomSheetDialog.window?.apply {
            setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT))
        }

        bottomSheetDialog.setOnShowListener {
            val bottomSheet = bottomSheetDialog.findViewById<View>(com.google.android.material.R.id.design_bottom_sheet)
            bottomSheet?.apply {
                setBackgroundColor(android.graphics.Color.TRANSPARENT)
                elevation = 0f
            }
        }
			
        bottomSheetDialog.show()
    }

    // Authenticated Background Stream Storage Pipeline
    private fun saveImageToDCIM(url: String) {
        val userAgent = webView.settings.userAgentString
        val cleanFileName = "Enclavd_${System.currentTimeMillis()}.jpg"
		
        Toast.makeText(applicationContext, "Saving image to DCIM/Enclavd...", Toast.LENGTH_SHORT).show()

        thread {
            try {
                val connection = URL(url).openConnection() as HttpURLConnection
                connection.requestMethod = "GET"
                connection.setRequestProperty("User-Agent", userAgent)
                connection.connect()

                if (connection.responseCode == HttpURLConnection.HTTP_OK) {
                    val inputStream: InputStream = connection.inputStream
                    val resolver = contentResolver
					
                    val contentValues = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, cleanFileName)
                        put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
                        put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DCIM + "/Enclavd")
                    }

                    val imageUri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                    if (imageUri != null) {
                        val outputStream: OutputStream? = resolver.openOutputStream(imageUri)
                        if (outputStream != null) {
                            val buffer = ByteArray(4096)
                            var bytesRead: Int
                            while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                                outputStream.write(buffer, 0, bytesRead)
                            }
                            outputStream.close()
                        }
                        inputStream.close()

                        runOnUiThread {
                            Toast.makeText(applicationContext, "Image saved successfully!", Toast.LENGTH_SHORT).show()
                        }
                    }
                } else {
                    runOnUiThread {
                        Toast.makeText(applicationContext, "Server rejected request (Error ${connection.responseCode})", Toast.LENGTH_LONG).show()
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
                runOnUiThread {
                    Toast.makeText(applicationContext, "Save failed: ${e.localizedMessage}", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun triggerStandardDownload(url: String, userAgent: String?, contentDisposition: String?, mimeType: String?) {
        val request = DownloadManager.Request(Uri.parse(url)).apply {
            if (mimeType != null) setMimeType(mimeType)
            if (userAgent != null) addRequestHeader("User-Agent", userAgent)
            setDescription("Saving image...")
            setTitle(URLUtil.guessFileName(url, contentDisposition, mimeType))
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, URLUtil.guessFileName(url, contentDisposition, mimeType))
        }

        val dm = getSystemService(DOWNLOAD_SERVICE) as DownloadManager?
        if (dm != null) {
            dm.enqueue(request)
            Toast.makeText(applicationContext, "Saving image...", Toast.LENGTH_LONG).show()
        }
    }

    private fun showErrorScreen() {
        webView.visibility = View.GONE
        layoutError.visibility = View.VISIBLE
    }

    private fun showWebView() {
        layoutError.visibility = View.GONE
        webView.visibility = View.VISIBLE
    }

    override fun onBackPressed() {
        if (webView.canGoBack()) {
            webView.goBack()
        } else {
            super.onBackPressed()
        }
    }
	
    override fun onResume() {
        super.onResume()
        // If the app was backgrounded while an error screen was showing (e.g.
        // due to a spurious disconnect fired by the WebView on resume), attempt
        // a silent reload so the user doesn't have to tap "Try Again" manually.
        if (isError && hasLoadedOnce) {
            isError = false
            webView.reload()
        }
    }

    override fun onPause() {
        super.onPause()
        android.webkit.CookieManager.getInstance().flush()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Enclavd Notifications"
            val descriptionText = "Notifications for likes, comments, and follows"
            val importance = NotificationManager.IMPORTANCE_DEFAULT
            val channel = NotificationChannel("enclavd_notifications", name, importance).apply {
                description = descriptionText
            }
            val notificationManager: NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }
    }

    private fun scheduleNotificationWorker() {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val workRequest = PeriodicWorkRequestBuilder<NotificationWorker>(15, TimeUnit.MINUTES)
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            "EnclavdNotificationWork",
            ExistingPeriodicWorkPolicy.REPLACE,
            workRequest
        )
    }
}