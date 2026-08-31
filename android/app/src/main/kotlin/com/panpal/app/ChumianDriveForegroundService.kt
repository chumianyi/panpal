package com.panpal.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ChumianDriveForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "chumian_drive_service"
        const val NOTIFICATION_ID = 1001
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"

        fun start(context: Context, title: String, body: String) {
            val intent = Intent(context, ChumianDriveForegroundService::class.java).apply {
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, ChumianDriveForegroundService::class.java)
            context.stopService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "初眠网盘运行中"
        val body = intent?.getStringExtra(EXTRA_BODY) ?: "本地HTTP服务器正在运行"
        startForeground(NOTIFICATION_ID, createNotification(title, body))
        return START_STICKY
    }

    private fun createNotification(title: String, body: String): Notification {
        createNotificationChannel()
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "初眠网盘服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "初眠网盘本地HTTP服务器运行通知"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
