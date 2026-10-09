package com.abuseif.punisherdrive

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.webkit.WebResourceRequest
import android.provider.MediaStore
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.FileOutputStream
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : Activity() {
    private lateinit var web: WebView
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var cameraUri: Uri? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cameraUri = savedInstanceState?.getString(CAMERA_URI_STATE)?.let(Uri::parse)
        web = WebView(this)
        web.setBackgroundColor(android.graphics.Color.rgb(5, 7, 11))
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.settings.cacheMode = WebSettings.LOAD_DEFAULT
        // Local assets may read their packaged resources, never arbitrary file URLs.
        web.settings.allowFileAccessFromFileURLs = false
        web.settings.allowUniversalAccessFromFileURLs = false
        // Never expose AndroidDocs to a website loaded by a navigation.
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean =
                handleNavigation(request?.url)

            @Suppress("DEPRECATION")
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean =
                handleNavigation(url?.let(Uri::parse))
        }
        web.addJavascriptInterface(DocumentBridge(), "AndroidDocs")

        web.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(
                webView: WebView?,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                this@MainActivity.fileCallback?.onReceiveValue(null)
                this@MainActivity.fileCallback = filePathCallback

                val galleryIntent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                }

                val cameraIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
                val initialIntents = mutableListOf<Intent>()

                if (cameraIntent.resolveActivity(packageManager) != null) {
                    val dir = File(cacheDir, "camera").apply { mkdirs() }
                    val photo = File.createTempFile("punisher_", ".jpg", dir)
                    val uri = FileProvider.getUriForFile(
                        this@MainActivity,
                        "${packageName}.fileprovider",
                        photo
                    )
                    cameraUri = uri
                    cameraIntent.putExtra(MediaStore.EXTRA_OUTPUT, uri)
                    cameraIntent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    initialIntents.add(cameraIntent)
                }

                val chooser = Intent(Intent.ACTION_CHOOSER).apply {
                    putExtra(Intent.EXTRA_INTENT, galleryIntent)
                    putExtra(Intent.EXTRA_TITLE, "Punisher Drive")
                    putExtra(Intent.EXTRA_INITIAL_INTENTS, initialIntents.toTypedArray())
                }

                startActivityForResult(chooser, FILE_CHOOSER_REQUEST)
                return true
            }
        }

        web.loadUrl("file:///android_asset/index.html")
        setContentView(web)
    }

    private fun handleNavigation(uri: Uri?): Boolean {
        if (uri == null) return true
        val url = uri.toString()
        if (url.startsWith("file:///android_asset/") || url == "about:blank") return false

        // Open links in the system browser/dialer, not in this privileged WebView.
        if (uri.scheme in setOf("https", "http", "mailto", "tel")) {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE))
            } catch (_: ActivityNotFoundException) {
                // No matching application: simply block navigation in our WebView.
            }
        }
        return true
    }

    override fun onSaveInstanceState(outState: Bundle) {
        cameraUri?.let { outState.putString(CAMERA_URI_STATE, it.toString()) }
        super.onSaveInstanceState(outState)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == FILE_CHOOSER_REQUEST) {
            val callback = fileCallback
            fileCallback = null

            if (resultCode != RESULT_OK) {
                cameraUri = null
                callback?.onReceiveValue(null)
                return
            }

            val result = when {
                data?.data != null -> arrayOf(data.data!!)
                cameraUri != null -> arrayOf(cameraUri!!)
                else -> null
            }

            callback?.onReceiveValue(result)
            cameraUri = null
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }

    inner class DocumentBridge {
        // Only opaque garage IDs generated by our app are accepted. This keeps
        // document storage confined to a single vehicle's private directory.
        private fun safeVehicleId(id: String): String? =
            id.takeIf { it.length in 1..100 && it.matches(Regex("[A-Za-z0-9_-]+")) }

        private fun safeKind(kind: String): String? =
            kind.takeIf { it == "annual" || it == "unified" }

        @JavascriptInterface
        fun saveDocument(vehicleId: String, kind: String, dataUrl: String): String {
            val id = safeVehicleId(vehicleId) ?: return ""
            val documentKind = safeKind(kind) ?: return ""
            if (!dataUrl.startsWith("data:image/jpeg;base64,")) return ""
            val encoded = dataUrl.substringAfter(',', "")
            if (encoded.isEmpty() || encoded.length > MAX_DOCUMENT_BASE64_CHARS) return ""

            return try {
                val raw = Base64.decode(encoded, Base64.DEFAULT)
                if (raw.size < 4 || raw.size > MAX_DOCUMENT_BYTES ||
                    raw[0] != 0xFF.toByte() || raw[1] != 0xD8.toByte() ||
                    raw[raw.size - 2] != 0xFF.toByte() || raw[raw.size - 1] != 0xD9.toByte()
                ) return ""

                val folder = File(filesDir, "customer_docs/$id")
                if (!folder.isDirectory && !folder.mkdirs()) return ""
                val target = File(folder, "$documentKind.jpg")
                val temp = File.createTempFile("document_", ".tmp", folder)
                try {
                    FileOutputStream(temp).use { stream ->
                        stream.write(raw)
                        stream.fd.sync()
                    }
                    if (!temp.renameTo(target)) return ""
                    // JS needs only a success flag; don't expose private filesystem paths.
                    "saved"
                } finally {
                    if (temp.exists()) temp.delete()
                }
            } catch (_: Exception) {
                ""
            }
        }

        @JavascriptInterface
        fun hasDocument(vehicleId: String, kind: String): Boolean {
            val id = safeVehicleId(vehicleId) ?: return false
            val documentKind = safeKind(kind) ?: return false
            return File(filesDir, "customer_docs/$id/$documentKind.jpg").isFile
        }

        @JavascriptInterface
        fun deleteDocument(vehicleId: String, kind: String): Boolean {
            val id = safeVehicleId(vehicleId) ?: return false
            val documentKind = safeKind(kind) ?: return false
            return File(filesDir, "customer_docs/$id/$documentKind.jpg").delete()
        }
    }

    companion object {
        private const val FILE_CHOOSER_REQUEST = 4917
        private const val CAMERA_URI_STATE = "punisher.cameraUri"
        private const val MAX_DOCUMENT_BYTES = 10 * 1024 * 1024
        private const val MAX_DOCUMENT_BASE64_CHARS = 14 * 1024 * 1024
    }
}
