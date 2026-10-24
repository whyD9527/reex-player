package io.github.whyd9527.reex_player

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 承载 Flutter 的 Activity：
 *  - 外部 VIEW 意图的 URI 通过 reex_player/intent 通道交给 Dart
 *  - pickVideo：用 SAF 选片，复制到 cacheDir 后返回本地绝对路径
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var pendingUri: String? = null
    private var pendingPick: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingUri = intent?.dataString
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "reex_player/intent")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialUri" -> {
                    result.success(pendingUri)
                    pendingUri = null
                }
                "pickVideo" -> openDocument(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun openDocument(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "another picker is open", null)
            return
        }
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
        }
        try {
            startActivityForResult(intent, REQ_PICK)
        } catch (e: Exception) {
            pendingPick = null
            result.error("no_picker", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_PICK) {
            val result = pendingPick
            pendingPick = null
            val uri: Uri? = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                result?.success(null)
                return
            }
            try {
                result?.success(copyToCache(uri))
            } catch (e: Exception) {
                result?.error("copy_failed", e.message, null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun copyToCache(uri: Uri): String {
        val name = displayName(uri) ?: "picked_${System.currentTimeMillis()}.mp4"
        val out = File(cacheDir, name)
        contentResolver.openInputStream(uri)!!.use { input ->
            out.outputStream().use { output -> input.copyTo(output) }
        }
        return out.absolutePath
    }

    private fun displayName(uri: Uri): String? {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) cursor.getString(idx) else null
            } else {
                null
            }
        } finally {
            cursor?.close()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val uri = intent.dataString ?: return
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("onNewUri", uri)
        } else {
            pendingUri = uri
        }
    }

    companion object {
        private const val REQ_PICK = 0x5EED
    }
}
