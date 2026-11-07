package com.cypher.cypher

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.PersistableBundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val text = call.argument<String>("text")
                if (text == null) {
                    result.error("bad_args", "text is required", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "copySensitive" -> {
                        copySensitive(text)
                        result.success(null)
                    }
                    "clearIfUnchanged" -> {
                        clearIfUnchanged(text)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private val clipboard: ClipboardManager
        get() = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    /** Copies a one-time code, flagged sensitive so Android 13+ hides it in previews. */
    private fun copySensitive(text: String) {
        val clip = ClipData.newPlainText("One-time code", text)
        clip.description.extras = PersistableBundle().apply {
            val key = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                ClipDescription.EXTRA_IS_SENSITIVE
            } else {
                "android.content.extra.IS_SENSITIVE"
            }
            putBoolean(key, true)
        }
        clipboard.setPrimaryClip(clip)
    }

    /**
     * Clears the clipboard unless it visibly holds something else. In the
     * background Android hides the clipboard (primaryClip is null), so the
     * code is cleared then too: leaving it would be worse.
     */
    private fun clearIfUnchanged(text: String) {
        val current = clipboard.primaryClip
        if (current != null && current.itemCount > 0 &&
            current.getItemAt(0).text?.toString() != text
        ) {
            return
        }
        clipboard.clearPrimaryClip()
    }

    private companion object {
        const val CHANNEL = "cypher/platform"
    }
}
