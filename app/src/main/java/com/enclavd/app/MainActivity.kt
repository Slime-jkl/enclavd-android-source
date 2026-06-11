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
		
		// Main Container with Material styling
		val linearLayout = LinearLayout(context).apply {
			orientation = LinearLayout.VERTICAL
			layoutParams = ViewGroup.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT, 
				ViewGroup.LayoutParams.WRAP_CONTENT
			)
			setPadding(0, 48, 0, 64) // Material spacing
			
			// Force a clean white/surface background with rounded top corners
			val shape = android.graphics.drawable.GradientDrawable().apply {
				setColor(android.graphics.Color.WHITE)
				cornerRadii = floatArrayOf(40f, 40f, 40f, 40f, 0f, 0f, 0f, 0f) // Top corners rounded
			}
			background = shape
		}

		// Material 3 Drag Handle Indicator
		val dragHandle = View(context).apply {
			layoutParams = LinearLayout.LayoutParams(96, 12).apply {
				gravity = android.view.Gravity.CENTER_HORIZONTAL
				setMargins(0, 0, 0, 48)
			}
			val handleShape = android.graphics.drawable.GradientDrawable().apply {
				setColor(android.graphics.Color.LTGRAY)
				cornerRadius = 6f
			}
			background = handleShape
		}
		linearLayout.addView(dragHandle)

		// Material Header/Title
		val title = TextView(context).apply {
			layoutParams = LinearLayout.LayoutParams(
				LinearLayout.LayoutParams.MATCH_PARENT,
				LinearLayout.LayoutParams.WRAP_CONTENT
			)
			text = "Image Options"
			textSize = 16f
			typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
			textAlignment = View.TEXT_ALIGNMENT_CENTER
			setPadding(0, 0, 0, 32)
			setTextColor(android.graphics.Color.parseColor("#49454F")) // Material Variant Color
		}
		linearLayout.addView(title)

		// Material Action Row (Clickable Item)
		val saveOption = TextView(context).apply {
			layoutParams = LinearLayout.LayoutParams(
				LinearLayout.LayoutParams.MATCH_PARENT,
				LinearLayout.LayoutParams.WRAP_CONTENT
			)
			text = "Save Image to Gallery"
			textSize = 18f
			typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
			setPadding(64, 40, 64, 40)
			setTextColor(android.graphics.Color.parseColor("#1D1B20")) // Material Main Text Color
			
			// Add native Material ripple effect on click
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
		
		// Remove default dialog background dim and shadows that break the shape
		bottomSheetDialog.window?.findViewById<View>(com.google.android.material.R.id.design_bottom_sheet)
			?.setBackgroundColor(android.graphics.Color.TRANSPARENT)
			
		bottomSheetDialog.show()
	}

    // DOWNLOAD DIRECTLY TO DCIM/Enclavd & FORCE MEDIA SCANNING
	private fun saveImageToDCIM(url: String) {
		val userAgent = webView.settings.userAgentString
		val fileName = URLUtil.guessFileName(url, null, "image/jpeg")
		
		// Explicit targeted relative path inside the public DCIM directory
		val subPath = "Enclavd/$fileName"

		val request = DownloadManager.Request(Uri.parse(url)).apply {
			setMimeType("image/jpeg")  
			addRequestHeader("User-Agent", userAgent)
			setDescription("Saving image to Enclavd folder...")
			setTitle(fileName)
			setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
			
			// This is the correct way to target subfolders in shared storage
			setDestinationInExternalPublicDir(Environment.DIRECTORY_DCIM, subPath)
		}

		val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager?
		if (dm != null) {
			dm.enqueue(request)
			Toast.makeText(applicationContext, "Saving to DCIM/Enclavd...", Toast.LENGTH_LONG).show()

			// Get the absolute path for the media scanner to pick up the file immediately
			val dcimDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM)
			val targetFile = File(dcimDir, subPath)

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