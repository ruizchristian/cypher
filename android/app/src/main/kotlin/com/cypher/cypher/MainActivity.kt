package com.cypher.cypher

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.provider.DocumentsContract
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity is required by local_auth (biometric prompt).
class MainActivity : FlutterFragmentActivity() {
    // A backup waiting for the user to pick where to save it, and the Dart
    // call to answer once they have (or cancelled).
    private var pendingBackup: ByteArray? = null
    private var pendingResult: MethodChannel.Result? = null

    // Android's system "Save as" dialog (Storage Access Framework): the user
    // picks the location, so the app needs no storage permission.
    private val createDocument =
        registerForActivityResult(
            ActivityResultContracts.CreateDocument("application/octet-stream"),
        ) { uri -> finishSave(uri) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots, screen recording and the recents thumbnail in
        // every build (docs/system-plan.md, M5).
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "copySensitive", "clearIfUnchanged" -> {
                        val text = call.argument<String>("text")
                        if (text == null) {
                            result.error("bad_args", "text is required", null)
                        } else {
                            if (call.method == "copySensitive") {
                                copySensitive(text)
                            } else {
                                clearIfUnchanged(text)
                            }
                            result.success(null)
                        }
                    }
                    "saveBackup" -> {
                        val name = call.argument<String>("name")
                        val bytes = call.argument<ByteArray>("bytes")
                        when {
                            name == null || bytes == null ->
                                result.error("bad_args", "name and bytes are required", null)
                            pendingResult != null ->
                                result.error("busy", "a save is already in progress", null)
                            else -> {
                                pendingBackup = bytes
                                pendingResult = result
                                createDocument.launch(name)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // In-app updates (lib/features/update/update_platform.dart). Downloading
        // happens in Dart; this covers what Dart cannot do: read the
        // versionCode and open the package installer.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATES_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installedVersion" -> {
                        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(
                                packageName,
                                PackageManager.PackageInfoFlags.of(0),
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, 0)
                        }
                        result.success(
                            mapOf("version" to info.versionName, "build" to info.longVersionCode),
                        )
                    }
                    "cacheDirectory" -> result.success(cacheDir.absolutePath)
                    "canInstall" -> result.success(packageManager.canRequestPackageInstalls())
                    "openInstallSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                        result.success(null)
                    }
                    "install" -> result.success(install(call.argument<String>("path")))
                    else -> result.notImplemented()
                }
            }
    }

    /** Opens the system installer on a downloaded APK; Android asks the user to confirm. */
    private fun install(path: String?): Boolean {
        if (path == null) return false
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(path))
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Writes the pending backup to [uri] and answers Dart with true, or false
     * if the user cancelled.
     *
     * The write runs on a background thread: cloud document providers (e.g.
     * Google Drive) can block inside openOutputStream/write, which on the
     * main thread would freeze the app. If the write fails, the empty file
     * the system just created is removed.
     */
    private fun finishSave(uri: Uri?) {
        val result = pendingResult ?: return
        val bytes = pendingBackup
        pendingResult = null
        pendingBackup = null
        if (uri == null || bytes == null) {
            result.success(false)
            return
        }
        Thread {
            val error = try {
                writeDocument(uri, bytes)
                null
            } catch (e: Exception) {
                // The message names the failure type, never the contents.
                runCatching { DocumentsContract.deleteDocument(contentResolver, uri) }
                e.javaClass.simpleName
            } finally {
                bytes.fill(0)
            }
            runOnUiThread {
                if (error == null) {
                    result.success(true)
                } else {
                    result.error("write_failed", error, null)
                }
            }
        }.start()
    }

    /**
     * Truncate-and-write ("wt") is not supported by every document provider;
     * plain "w" is equivalent here because CreateDocument has just made an
     * empty file.
     */
    private fun writeDocument(uri: Uri, bytes: ByteArray) {
        val stream = try {
            contentResolver.openOutputStream(uri, "wt")
        } catch (e: IllegalArgumentException) {
            contentResolver.openOutputStream(uri, "w")
        } ?: throw java.io.IOException("could not open the chosen file")
        stream.use { it.write(bytes) }
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
        const val UPDATES_CHANNEL = "cypher/updates"
    }
}
