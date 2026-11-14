package com.ikram.ikram_browser

import android.content.Context
import android.webkit.CookieManager
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewDatabase
import androidx.webkit.WebStorageCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object IkramPrivacy {
    private var clearing = false

    fun install(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "ikram_safe/privacy").setMethodCallHandler { call, result ->
            if (call.method != "clearAll") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (clearing) {
                result.error("CLEANUP_BUSY", "Cleanup is already running", null)
                return@setMethodCallHandler
            }
            clearing = true
            try {
                // Flutter destroys its WebView before invoking this method.
                val storage = WebStorage.getInstance()
                val complete = WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)
                val finish = Runnable {
                    CookieManager.getInstance().removeAllCookies {
                        try {
                            CookieManager.getInstance().flush()
                            WebViewDatabase.getInstance(context).clearHttpAuthUsernamePassword()
                            val cleaner = WebView(context)
                            cleaner.clearCache(true)
                            cleaner.clearHistory()
                            @Suppress("DEPRECATION")
                            cleaner.clearFormData()
                            cleaner.destroy()
                            clearing = false
                            result.success(mapOf("complete" to complete))
                        } catch (error: Exception) {
                            clearing = false
                            result.error("CLEANUP_FAILED", "Could not finish local cleanup", null)
                        }
                    }
                }
                if (complete) {
                    WebStorageCompat.deleteBrowsingData(storage, finish)
                } else {
                    // Old providers cannot promise all-origin IndexedDB/cache
                    // removal. Report partial cleanup instead of false success.
                    storage.deleteAllData()
                    finish.run()
                }
            } catch (error: Exception) {
                clearing = false
                result.error("CLEANUP_FAILED", "Could not clear local website data", null)
            }
        }
    }
}
