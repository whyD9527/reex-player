package io.github.whyd9527.reex_player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import io.flutter.plugin.common.MethodChannel

/**
 * 前台播放服务：
 *  - 常驻媒体通知（播放/暂停、±10s、停止）
 *  - MediaSession 供锁屏/蓝牙控制
 *  - 把控制命令通过 reex_player/playback 通道回传给 Dart
 */
class PlaybackService : Service() {

    companion object {
        const val CHANNEL_ID = "reex_playback"
        const val NOTIFICATION_ID = 0x5258
        const val ACTION_TOGGLE = "io.github.whyd9527.reex_player.TOGGLE"
        const val ACTION_BACK = "io.github.whyd9527.reex_player.BACK10"
        const val ACTION_FWD = "io.github.whyd9527.reex_player.FWD10"
        const val ACTION_STOP = "io.github.whyd9527.reex_player.STOP"

        var channel: MethodChannel? = null
        var currentTitle: String = ""
        var currentDuration: Long = 0
        var currentPosition: Long = 0
        var isPlaying: Boolean = false
    }

    private lateinit var session: MediaSession

    override fun onCreate() {
        super.onCreate()
        createChannel()
        session = MediaSession(this, "ReexPlayer").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = send("play")
                override fun onPause() = send("pause")
                override fun onStop() = send("stop")
                override fun onSeekTo(pos: Long) = send("seek:\$pos")
            })
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "update" -> { /* 仅刷新通知 */ }
            ACTION_TOGGLE -> send(if (isPlaying) "pause" else "play")
            ACTION_BACK -> send("back")
            ACTION_FWD -> send("forward")
            ACTION_STOP -> {
                send("stop")
                stopSelf()
                return START_NOT_STICKY
            }
        }
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, n, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
        updateState()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun send(cmd: String) {
        channel?.invokeMethod("command", cmd, object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(code: String, msg: String?, details: Any?) {}
            override fun notImplemented() {}
        })
        if (cmd == "play") {
            isPlaying = true
        } else if (cmd == "pause") {
            isPlaying = false
        }
        notifyUpdate()
    }

    fun notifyUpdate() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification())
        updateState()
    }

    private fun updateState() {
        val state = if (isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        session.setPlaybackState(
            PlaybackState.Builder()
                .setActions(
                    PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                        PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SEEK_TO or
                        PlaybackState.ACTION_STOP
                )
                .setState(state, currentPosition, if (isPlaying) 1.0f else 0.0f)
                .build()
        )
        session.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, currentTitle)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, currentDuration)
                .build()
        )
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "播放", NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(ch)
        }
    }

    private fun pending(action: String, code: Int): PendingIntent {
        val i = Intent(this, PlaybackService::class.java).setAction(action)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getService(this, code, i, flags)
    }

    private fun buildNotification(): Notification {
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val content = PendingIntent.getActivity(
            this, 0, open,
            PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setContentTitle(currentTitle.ifEmpty { "Reex Player" })
            .setContentText(if (isPlaying) "正在播放" else "已暂停")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(content)
            .setOngoing(isPlaying)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(this, android.R.drawable.ic_media_rew),
                    "-10s", pending(ACTION_BACK, 1)
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(
                        this,
                        if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
                    ),
                    if (isPlaying) "暂停" else "播放", pending(ACTION_TOGGLE, 2)
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(this, android.R.drawable.ic_media_ff),
                    "+10s", pending(ACTION_FWD, 3)
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
                    "停止", pending(ACTION_STOP, 4)
                ).build()
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            builder.setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken).setShowActionsInCompactView(0, 1, 2))
        }
        return builder.build()
    }
}