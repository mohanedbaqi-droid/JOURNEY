package com.abuseif.punisherdrive

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.MediaStore
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : Activity() {
    private lateinit var web: WebView
    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var cameraUri: Uri? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        web = WebView(this)
        web.setBackgroundColor(android.graphics.Color.rgb(5, 7, 11))
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.settings.cacheMode = WebSettings.LOAD_DEFAULT
        web.webViewClient = WebViewClient()
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == FILE_CHOOSER_REQUEST) {
            val callback = fileCallback
            fileCallback = null

            if (resultCode != RESULT_OK) {
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
        @JavascriptInterface
        fun saveDocument(vehicleId: String, kind: String, dataUrl: String): String {
            return try {
                val comma = dataUrl.indexOf(',')
                if (comma < 0) return ""
                val raw = Base64.decode(dataUrl.substring(comma + 1), Base64.DEFAULT)

                val safeVehicle = vehicleId.replace(Regex("[^A-Za-z0-9_-]"), "_")
                val safeKind = if (kind == "unified") "unified" else "annual"
                val folder = File(filesDir, "customer_docs/$safeVehicle").apply { mkdirs() }
                val target = File(folder, "$safeKind.jpg")
                target.writeBytes(raw)
                target.absolutePath
            } catch (_: Throwable) {
                ""
            }
        }

        @JavascriptInterface
        fun hasDocument(vehicleId: String, kind: String): Boolean {
            val safeVehicle = vehicleId.replace(Regex("[^A-Za-z0-9_-]"), "_")
            val safeKind = if (kind == "unified") "unified" else "annual"
            return File(filesDir, "customer_docs/$safeVehicle/$safeKind.jpg").exists()
        }

        @JavascriptInterface
        fun deleteDocument(vehicleId: String, kind: String): Boolean {
            val safeVehicle = vehicleId.replace(Regex("[^A-Za-z0-9_-]"), "_")
            val safeKind = if (kind == "unified") "unified" else "annual"
            return File(filesDir, "customer_docs/$safeVehicle/$safeKind.jpg").delete()
        }
    }

    companion object {
        private const val FILE_CHOOSER_REQUEST = 4917
    }
}
