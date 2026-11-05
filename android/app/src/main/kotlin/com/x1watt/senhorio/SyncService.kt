package com.x1watt.senhorio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/**
 * Foreground service that keeps the process (and the cached Flutter engine,
 * see MainActivity) alive so the Reticulum sync keeps running with the app in
 * the background. Dart timers are throttled in the background, a native
 * Handler is not, so this drives a heartbeat into Dart ("onTick" on the
 * com.x1watt.senhorio/bg channel). Pattern from xprs BgService.
 *
 * Type connectedDevice (not dataSync, which Android 15 stops after 6 hours a
 * day); its Android 14 prerequisite is CHANGE_WIFI_MULTICAST_STATE, which the
 * LAN discovery needs anyway.
 */
class SyncService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private val ticker = object : Runnable {
        override fun run() {
            // A short wake lock per tick: enough for Dart to reconnect hubs,
            // announce and say hello, impossible to leak.
            try {
                wakeLock?.acquire(20_000L)
            } catch (_: Throwable) {
            }
            try {
                MainActivity.channel?.invokeMethod("onTick", null)
            } catch (_: Throwable) {
            }
            handler.postDelayed(this, TICK_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "senhorio:sync").apply {
            setReferenceCounted(false)
        }
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("senhorio-sync").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Throwable) {
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "Senhorio"
        val text = intent?.getStringExtra("text") ?: "Sync active"
        val notification = buildNotification(title, text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        handler.removeCallbacks(ticker)
        handler.postDelayed(ticker, TICK_MS)
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacks(ticker)
        try {
            multicastLock?.release()
        } catch (_: Throwable) {
        }
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Throwable) {
        }
        super.onDestroy()
    }

    private fun buildNotification(title: String, text: String): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Sync", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Background sync with the members of your buildings"
                    setShowBadge(false)
                }
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return b.setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "senhorio_sync"
        const val NOTIFICATION_ID = 4242
        const val TICK_MS = 60_000L

        @Volatile
        var running = false
    }
}
