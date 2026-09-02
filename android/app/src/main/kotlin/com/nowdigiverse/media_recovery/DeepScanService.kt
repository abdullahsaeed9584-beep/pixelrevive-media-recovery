package com.nowdigiverse.media_recovery

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class DeepScanService : Service() {

    companion object {
        const val CHANNEL_ID = "deep_scan_channel"
        const val NOTIFICATION_ID = 2002
        
        var isRunning = false
            private set
            
        private var currentService: DeepScanService? = null
        
        fun updateProgress(context: Context, percent: Int) {
            if (!isRunning) return
            currentService?.updateNotification(percent)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        isRunning = true
        currentService = this
        
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Deep Scan Active")
            .setContentText("Scanning for recoverable files...")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setProgress(100, 0, true)
            .setOngoing(true)
            .build()
            
        startForeground(NOTIFICATION_ID, notification)
        return START_NOT_STICKY
    }

    private fun updateNotification(percent: Int) {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Deep Scan Active")
            .setContentText("Scanning for recoverable files... $percent%")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setProgress(100, percent, percent == 0)
            .setOngoing(true)
            .build()
            
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Deep Scan Progress",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows progress of active deep scans"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        isRunning = false
        currentService = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
