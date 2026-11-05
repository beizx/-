package com.yiyue.translation_app

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * Serves two Flutter engines channels:
 *
 * `.../reader`: keeps the screen awake while reading.
 * `.../files`: receives documents opened from other apps (QQ's "用其他应用打开"
 * arrives as ACTION_VIEW with a content:// URI) and copies them into the cache
 * directory so Dart can import them like a picked file.
 *
 * Extends `AudioServiceActivity` (a `FlutterActivity`) so the audio_service
 * plugin can share the Flutter engine with its media-playback foreground
 * service; that service is what keeps 听书 alive with the screen off and
 * renders the lock screen / notification controls.
 */
class MainActivity : AudioServiceActivity() {
    private var filesChannel: MethodChannel? = null
    private var volumeChannel: MethodChannel? = null
    private var pendingImport: Map<String, String>? = null
    private var captureVolumeKeys = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.yiyue.translation_app/reader")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepScreenOn" -> {
                        if (call.arguments as? Boolean == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "openBackgroundSettings" -> result.success(openBackgroundSettings())
                    else -> result.notImplemented()
                }
            }

        volumeChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.yiyue.translation_app/volume")
                .also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "setCapture" -> {
                                captureVolumeKeys = call.arguments as? Boolean == true
                                result.success(null)
                            }
                            else -> result.notImplemented()
                        }
                    }
                }

        filesChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.yiyue.translation_app/files")
                .also { channel ->
                    channel.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "takePendingFile" -> {
                                val pending = pendingImport
                                pendingImport = null
                                result.success(pending)
                            }
                            else -> result.notImplemented()
                        }
                    }
                }

        // A cold start from QQ / a file manager arrives through this intent.
        handleIncomingIntent(intent)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val isVolume =
            event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN
        if (captureVolumeKeys && isVolume) {
            if (event.action == KeyEvent.ACTION_DOWN) {
                val direction = if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) -1 else 1
                volumeChannel?.invokeMethod("onVolumeKey", direction)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    /**
     * Opens the system battery-optimization list when the ROM allows it, and
     * falls back to this app's details page. Never requests the restricted
     * ignore-battery-optimizations permission.
     */
    private fun openBackgroundSettings(): Boolean {
        val battery = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val details = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(battery)
            true
        } catch (error: Exception) {
            try {
                startActivity(details)
                true
            } catch (fallback: Exception) {
                false
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        val uri: Uri? =
            when (intent.action) {
                Intent.ACTION_VIEW -> intent.data
                Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
                else -> null
            }
        if (uri == null) return

        val payload = copyToCache(uri) ?: return
        pendingImport = payload
        // If Dart is already listening, push it right away; otherwise the
        // pending payload is drained on the next takePendingFile call.
        filesChannel?.invokeMethod("onFileOpened", payload)
    }

    /** Copies the shared document into the cache and describes it for Dart. */
    private fun copyToCache(uri: Uri): Map<String, String>? {
        val displayName = resolveDisplayName(uri) ?: "incoming.txt"
        val extension = displayName.substringAfterLast('.', "").lowercase()
        if (extension != "txt" && extension != "epub") {
            // Ignore formats we cannot read instead of failing on an arbitrary
            // ACTION_VIEW sent by another app.
            return null
        }
        return try {
            val dir = File(cacheDir, "external_import").apply { mkdirs() }
            val target = File(dir, "${UUID.randomUUID()}-$displayName")
            val input = contentResolver.openInputStream(uri) ?: return null
            input.use { source ->
                target.outputStream().use { sink -> source.copyTo(sink) }
            }
            mapOf("path" to target.absolutePath, "name" to displayName)
        } catch (error: Exception) {
            null
        }
    }

    private fun resolveDisplayName(uri: Uri): String? {
        if (uri.scheme == "content") {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) {
                        val name = cursor.getString(0)
                        if (!name.isNullOrBlank()) return name
                    }
                }
        }
        return uri.lastPathSegment?.substringAfterLast('/')
    }
}
