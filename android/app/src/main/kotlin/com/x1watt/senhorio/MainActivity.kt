package com.x1watt.senhorio

import android.Manifest
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

    companion object {
        const val ENGINE_ID = "senhorio_engine"
        const val CHANNEL = "com.x1watt.senhorio/bg"

        /** Shared with SyncService for the heartbeat. */
        @Volatile
        var channel: MethodChannel? = null
    }
}
