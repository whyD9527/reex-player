package io.github.whyd9527.reex_player

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 承载 Flutter 的 Activity：
 *  - reex_player/intent : 外部 VIEW 意图 + SAF 选片
 *  - reex_player/media  : MediaStore 视频扫描 + 权限
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var mediaChannel: MethodChannel? = null
    private var pendingUri: String? = null
    private var pendingPick: MethodChannel.Result? = null
    private var pendingPermission: MethodChannel.Result? = null

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
        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "reex_player/media")
        val playback = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "reex_player/playback")
        PlaybackService.channel = playback
        playback.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), REQ_NOTIF)
                    }
                    val args = call.arguments as? Map<*, *>
                    PlaybackService.currentTitle = (args?.get("title") as? String) ?: ""
                    PlaybackService.currentDuration = ((args?.get("duration") as? Number) ?: 0).toLong()
                    PlaybackService.isPlaying = true
                    val intent = Intent(this, PlaybackService::class.java).setAction("start")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                    result.success(true)
                }
                "update" -> {
                    val args = call.arguments as? Map<*, *>
                    PlaybackService.currentTitle = (args?.get("title") as? String) ?: PlaybackService.currentTitle
                    PlaybackService.currentPosition = ((args?.get("position") as? Number) ?: 0).toLong()
                    PlaybackService.currentDuration = ((args?.get("duration") as? Number) ?: 0).toLong()
                    PlaybackService.isPlaying = (args?.get("playing") as? Boolean) ?: false
                    val intent = Intent(this, PlaybackService::class.java).setAction("update")
                    startService(intent)
                    result.success(true)
                }
                "stop" -> {
                    PlaybackService.isPlaying = false
                    stopService(Intent(this, PlaybackService::class.java))
                    result.success(true)
                }
                "keepScreenOn" -> {
                    val on = (call.arguments as? Boolean) ?: false
                    runOnUiThread {
                        if (on) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(true)
                }
                "setVolume" -> {
                    val v = ((call.arguments as? Number) ?: 1.0).toFloat()
                    val am = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
                    val max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                    am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, (v * max).toInt(), 0)
                    result.success(true)
                }
                "setBrightness" -> {
                    val v = ((call.arguments as? Number) ?: 0.5).toFloat()
                    runOnUiThread {
                        window.attributes = window.attributes.apply { screenBrightness = v.coerceIn(0.01f, 1f) }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        mediaChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "scanVideos" -> scanVideos(result)
                "thumbnail" -> thumbnail((call.arguments as? Number)?.toLong() ?: 0L, result)
                "ensurePermission" -> ensurePermission(result)
                else -> result.notImplemented()
            }
        }
    }

    // ---- 媒体库 ----

    private fun videoPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Manifest.permission.READ_MEDIA_VIDEO
        else Manifest.permission.READ_EXTERNAL_STORAGE

    private fun hasVideoPermission(): Boolean =
        checkSelfPermission(videoPermission()) == PackageManager.PERMISSION_GRANTED

    private fun ensurePermission(result: MethodChannel.Result) {
        if (hasVideoPermission()) {
            result.success(true)
            return
        }
        pendingPermission = result
        requestPermissions(arrayOf(videoPermission()), REQ_PERM)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == REQ_PERM) {
            val r = pendingPermission
            pendingPermission = null
            r?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    private fun scanVideos(result: MethodChannel.Result) {
        if (!hasVideoPermission()) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        val out = ArrayList<Map<String, Any?>>(256)
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.DATE_ADDED,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
        )
        try {
            contentResolver.query(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                projection, null, null,
                MediaStore.Video.Media.DATE_ADDED + " DESC"
            )?.use { c: Cursor ->
                while (c.moveToNext() && out.size < 5000) {
                    out.add(
                        mapOf(
                            "id" to c.getLong(0),
                            "name" to (c.getString(1) ?: ""),
                            "durationMs" to c.getLong(2),
                            "size" to c.getLong(3),
                            "path" to (c.getString(4) ?: ""),
                            "dateAdded" to c.getLong(5),
                            "width" to c.getInt(6),
                            "height" to c.getInt(7),
                        )
                    )
                }
            }
        } catch (e: Exception) {
            result.error("scan_failed", e.message, null)
            return
        }
        result.success(out)
    }

    // ---- 选片 ----

    private fun thumbnail(id: Long, result: MethodChannel.Result) {
        try {
            val uri = android.content.ContentUris.withAppendedId(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI, id)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val bmp = contentResolver.loadThumbnail(uri, android.util.Size(256, 256), null)
                val out = java.io.ByteArrayOutputStream()
                bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 80, out)
                bmp.recycle()
                result.success(out.toByteArray())
            } else {
                result.success(null)
            }
        } catch (e: Exception) {
            result.success(null)
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
        val name = displayName(uri) ?: "picked_" + System.currentTimeMillis() + ".mp4"
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
        private const val REQ_PERM = 0x5EEE
        private const val REQ_NOTIF = 0x5EEF
    }
}