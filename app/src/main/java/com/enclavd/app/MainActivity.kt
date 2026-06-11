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
import java.io.File

class MainActivity : AppCompatActivity() {

    private lateinit var webView: WebView
    private lateinit var layoutError: RelativeLayout
    private lateinit var btnRetry: Button
    private lateinit var swipeRefresh: SwipeRefreshLayout
    private var isError = false

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
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        webView = findViewById(R.id.webView)
        layoutError = findViewById(R.id.layoutError)
        btnRetry = findViewById(R.id.btnRetry)
        swipeRefresh = findViewById(R.id.swipeRefresh)

        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.loadsImagesAutomatically = true
        webView.settings.allowFileAccess = true

        // MATERIAL UI LONG PRESS DETECTOR
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
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                swipeRefresh.isRefreshing = false
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

        swipeRefresh.setOnRefreshListener {
            webView.clearCache(true)
            webView.reload()
        }
    }

    // MODERN MATERIAL DESIGN BOTTOM SHEET DIALOG WITH FIXED DIMENSIONS
    private fun showMaterialBottomSheet(imageUrl: String) {
        val bottomSheetDialog = BottomSheetDialog(this)
        val context = this
        
        val linearLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setPadding(60, 60, 60, 80)
        }

        val title = TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            text = "Actions"
            textSize = 18f
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            setPadding(0, 10, 0, 50)
            setTextColor(resources.getColor(android.R.color.black, theme))
        }

        val saveOption = TextView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
            text = "Save Image"
            textSize = 16f
            setPadding(40, 40, 40, 40)
            setTextColor(resources.getColor(android.R.color.holo_blue_dark, theme))
            setOnClickListener {
                saveImageToDCIM(imageUrl)
                bottomSheetDialog.dismiss()
            }
        }

        linearLayout.addView(title)
        linearLayout.addView(saveOption)
        bottomSheetDialog.setContentView(linearLayout)
        bottomSheetDialog.show()
    }

    // DOWNLOAD DIRECTLY TO DCIM/Enclavd & FORCE MEDIA SCANNING
    private fun saveImageToDCIM(url: String) {
        val userAgent = webView.settings.userAgentString
        val fileName = URLUtil.guessFileName(url, null, "image/jpeg")
        
        val dcimDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM)
        val customFolder = File(dcimDir, "Enclavd")
        if (!customFolder.exists()) {
            customFolder.mkdirs()
        }
        
        val targetFile = File(customFolder, fileName)

        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setMimeType("image/jpeg")  
            addRequestHeader("User-Agent", userAgent)
            setDescription("Saving image...")
            setTitle(fileName)
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setDestinationUri(Uri.fromFile(targetFile))
        }

        val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager?
        if (dm != null) {
            dm.enqueue(request)
            Toast.makeText(applicationContext, "Saving to DCIM/Enclavd...", Toast.LENGTH_LONG).show()

            // Forces gallery visibility instantly 
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(targetFile.absolutePath),
                arrayOf("image/jpeg")
            ) { _, _ -> }
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
}