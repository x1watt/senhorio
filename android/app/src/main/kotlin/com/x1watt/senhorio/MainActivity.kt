package com.x1watt.senhorio

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Android drops inbound UDP broadcasts without a multicast lock, which
    // the Reticulum LAN discovery (port 42671) needs (pattern from xprs).
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("senhorio-lan").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
        }
    }

    override fun onDestroy() {
        try {
            multicastLock?.release()
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    /**
     * One engine for the whole process, kept in the cache: when the user
     * leaves the app the Activity goes away but Dart (and the sync) keep
     * running for as long as SyncService holds the process; reopening the
     * app attaches to the same engine.
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (channel != null) return
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            val ctx = applicationContext
            when (call.method) {
                "start" -> {
                    val i = Intent(ctx, SyncService::class.java)
                        .putExtra("title", call.argument<String>("title"))
                        .putExtra("text", call.argument<String>("text"))
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        ctx.startForegroundService(i)
                    } else {
                        ctx.startService(i)
                    }
                    result.success(true)
                }
                "stop" -> {
                    ctx.stopService(Intent(ctx, SyncService::class.java))
                    result.success(true)
                }
                "running" -> result.success(SyncService.running)
                // Opens the system installer on an APK downloaded to the cache
                // (res/xml/file_paths.xml); the user confirms the update there.
                "installApk" -> {
                    try {
                        val f = java.io.File(call.argument<String>("path")!!)
                        val uri = androidx.core.content.FileProvider.getUriForFile(
                            ctx, "${ctx.packageName}.fileprovider", f)
                        val i = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        ctx.startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("install", e.message, null)
                    }
                }
                // Copies a file into the public Downloads folder, which an
                // uninstall keeps (backups).
                "saveToDownloads" -> {
                    try {
                        val src = java.io.File(call.argument<String>("path")!!)
                        result.success(saveToDownloads(src, call.argument<String>("name")!!))
                    } catch (e: SecurityException) {
                        result.error("permission", e.message, null)
                    } catch (e: Exception) {
                        result.error("save", e.message, null)
                    }
                }
                // A permanent notification with what the tenant owes
                // (late rent, unpaid shared bills); cleared when settled.
                "showAlert" -> {
                    showAlert(call.argument<String>("title") ?: "", call.argument<String>("text") ?: "")
                    result.success(true)
                }
                "clearAlert" -> {
                    (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                        .cancel(ALERT_ID)
                    result.success(true)
                }
                // "A new version is ready": a normal notification that opens
                // the app, where the update dialog offers the install.
                "showUpdate" -> {
                    postNotification(UPDATE_ID, UPDATE_CHANNEL, "App updates", "A new version is ready to install",
                        call.argument<String>("title") ?: "", call.argument<String>("text") ?: "", ongoing = false)
                    result.success(true)
                }
                "clearUpdate" -> {
                    (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                        .cancel(UPDATE_ID)
                    result.success(true)
                }
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
    }

    private fun showAlert(title: String, text: String) =
        postNotification(ALERT_ID, ALERT_CHANNEL, "Payments due", "Late rent and unpaid shared bills",
            title, text, ongoing = true)

    /** One notification on its own channel; tapping it opens the app. */
    private fun postNotification(
        id: Int, channel: String, channelName: String, channelDescription: String,
        title: String, text: String, ongoing: Boolean
    ) {
        val ctx = applicationContext
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(channel, channelName, NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = channelDescription
                }
            )
        }
        val open = PendingIntent.getActivity(
            ctx, id,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        nm.notify(
            id,
            b.setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentIntent(open)
                .setOngoing(ongoing)
                .setAutoCancel(!ongoing)
                .setOnlyAlertOnce(true)
                .build()
        )
    }

    private fun saveToDownloads(src: java.io.File, name: String): String {
        if (Build.VERSION.SDK_INT >= 29) {
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Downloads.DISPLAY_NAME, name)
                put(android.provider.MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                put(android.provider.MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("MediaStore refused the file")
            resolver.openOutputStream(uri)!!.use { out -> src.inputStream().use { it.copyTo(out) } }
            values.clear()
            values.put(android.provider.MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Download/$name"
        }
        // Android 9 and older: the public folder needs the storage permission.
        if (checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 8)
            throw SecurityException("storage permission not granted yet")
        }
        val dir = android.os.Environment.getExternalStoragePublicDirectory(
            android.os.Environment.DIRECTORY_DOWNLOADS)
        dir.mkdirs()
        return src.copyTo(java.io.File(dir, name), overwrite = true).absolutePath
    }

    companion object {
        const val ENGINE_ID = "senhorio_engine"
        const val CHANNEL = "com.x1watt.senhorio/bg"
        const val ALERT_CHANNEL = "senhorio_alerts"
        const val ALERT_ID = 4243
        const val UPDATE_CHANNEL = "senhorio_updates"
        const val UPDATE_ID = 4244

        /** Shared with SyncService for the heartbeat. */
        @Volatile
        var channel: MethodChannel? = null
    }
}
