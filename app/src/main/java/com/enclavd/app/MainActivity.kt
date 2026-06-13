package com.enclavd.app

import android.annotation.SuppressLint
import android.app.DownloadManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaScannerConnection
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
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var layoutError: RelativeLayout
    private lateinit var btnRetry: Button
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private var isError = false
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

        webView = findViewById(R.id.webView)
        layoutError = findViewById(R.id.layoutError)
        btnRetry = findViewById(R.id.btnRetry)
        swipeRefresh = findViewById(R.id.swipeRefresh)
		splashOverlay = findViewById(R.id.splashOverlay)

        // Web State Engine Settings
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.databaseEnabled = true
        webView.settings.loadsImagesAutomatically = true
        webView.settings.allowFileAccess = true
		
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
                    if (intent != null) {
                        fileChooserLauncher.launch(intent)
                    }
                } catch (e: ActivityNotFoundException) {
                    uploadMessage = null
                    return false
                }
                return true
            }
        }

        webView.setDownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
            triggerStandardDownload(url, userAgent, contentDisposition, mimeType)
        }

        webView.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                super.onPageStarted(view, url, favicon)
                isError = false
            }

            override fun onReceivedError(view: WebView?, request: WebResourceRequest?, error: WebResourceError?) {
                super.onReceivedError(view, request, error)
                isError = true
                showErrorScreen()
                swipeRefresh.isRefreshing = false
				splashOverlay.visibility = View.GONE
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                swipeRefresh.isRefreshing = false
				splashOverlay.visibility = View.GONE
                if (!isError) {
                    showWebView()
                }
            }
        }

        val url = getString(R.string.website_url)
        webView.loadUrl(url)

        btnRetry.setOnClickListener {
            showWebView()
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
	
    override fun onPause() {
        super.onPause()
        android.webkit.CookieManager.getInstance().flush()
    }
}