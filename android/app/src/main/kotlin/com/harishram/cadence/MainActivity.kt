package com.harishram.cadence

import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Opens Android's own notification settings for Cadence.
 *
 * Sound, vibration and importance are owned by the OS from Android 8 onwards
 * — channels are immutable once created, so an in-app picker would have to
 * spawn a channel per sound and leave the old ones littering system settings.
 * Handing the user straight to the real controls is both less code and the
 * behaviour they already know.
 *
 * A MethodChannel rather than a plugin: this is one intent, and a dependency
 * for it would be more moving parts than the thing it replaces.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.harishram.cadence/settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> {
                        result.success(openNotificationSettings())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Returns false if no activity could handle the intent, rather than crashing. */
    private fun openNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            // Pre-Oreo has no per-app notification screen; the app details
            // page is the closest equivalent.
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(android.net.Uri.fromParts("package", packageName, null))
        }
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
