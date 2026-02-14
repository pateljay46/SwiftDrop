package com.swiftdrop.swiftdrop

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.swiftdrop/platform"
        private const val NOTIFICATION_CHANNEL_ID = "swiftdrop_transfer"
        private const val FOREGROUND_NOTIFICATION_ID = 1001
    }

    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    val title = call.argument<String>("title") ?: "SwiftDrop"
                    val body = call.argument<String>("body") ?: "Transferring files..."
                    startForegroundTransferService(title, body)
                    result.success(true)
                }
                "stopForegroundService" -> {
                    stopForegroundTransferService()
                    result.success(true)
                }
                "updateForegroundNotification" -> {
                    val title = call.argument<String>("title") ?: "SwiftDrop"
                    val body = call.argument<String>("body") ?: "Transferring..."
                    val progress = call.argument<Int>("progress")
                    updateNotification(title, body, progress)
                    result.success(true)
                }
                "isBatteryOptimizationDisabled" -> {
                    result.success(isBatteryOptimizationDisabled())
                }
                "requestBatteryOptimizationExemption" -> {
                    requestBatteryOptimizationExemption()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    // -------------------------------------------------------------------------
    // Notification channel
    // -------------------------------------------------------------------------

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "File Transfers",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notifications for active file transfers"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    // -------------------------------------------------------------------------
    // Foreground service
    // -------------------------------------------------------------------------

    private fun startForegroundTransferService(title: String, body: String) {
        val intent = Intent(this, TransferForegroundService::class.java).apply {
            putExtra("title", title)
            putExtra("body", body)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopForegroundTransferService() {
        val intent = Intent(this, TransferForegroundService::class.java)
        stopService(intent)
    }

    private fun updateNotification(title: String, body: String, progress: Int?) {
        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setSilent(true)

        if (progress != null) {
            builder.setProgress(100, progress.coerceIn(0, 100), false)
        }

        NotificationManagerCompat.from(this).notify(FOREGROUND_NOTIFICATION_ID, builder.build())
    }

    // -------------------------------------------------------------------------
    // Battery optimization
    // -------------------------------------------------------------------------

    private fun isBatteryOptimizationDisabled(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    @Suppress("BatteryLife")
    private fun requestBatteryOptimizationExemption() {
        if (!isBatteryOptimizationDisabled()) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        }
    }
}
