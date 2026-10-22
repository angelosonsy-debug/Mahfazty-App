package com.mahfazty.mahfazty

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val NOTIFICATIONS_CHANNEL = "mahfazty/notifications"
    private val SMS_CHANNEL = "mahfazty/sms"
    private val POWER_CHANNEL = "mahfazty/power"
    private val SMS_PERMISSION_REQUEST_CODE = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val notificationsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, NOTIFICATIONS_CHANNEL
        )
        MahfaztyNotificationListener.methodChannel = notificationsChannel

        notificationsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationAccessGranted" -> result.success(isNotificationAccessGranted())
                "openNotificationAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        val smsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)
        SmsReceiver.methodChannel = smsChannel

        smsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSmsPermissionGranted" -> result.success(isSmsPermissionGranted())
                "requestSmsPermission" -> {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_SMS),
                        SMS_PERMISSION_REQUEST_CODE
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // قناة استثناء تحسين البطارية — ضرورية عشان الخدمات الخلفية
        // (NotificationListener + SmsReceiver) تفضل شغالة على أجهزة
        // Xiaomi/Oppo/Huawei/Samsung اللي بتقفل الخدمات دي بقسوة افتراضيًا.
        val powerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, POWER_CHANNEL)
        powerChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(android.content.Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /// بيحاول يفتح الـ dialog المباشر لطلب الاستثناء (ACTION_REQUEST_
    /// IGNORE_BATTERY_OPTIMIZATIONS). بعض الأجهزة المعدّلة (خصوصًا
    /// Xiaomi/Huawei بـ ROM مُعدَّل) بترفض الـ intent ده أو تتجاهله، فلو
    /// فشل بنرجع لصفحة إعدادات توفير البطارية العامة، وآخر حل صفحة
    /// تفاصيل التطبيق العادية — مفيش احتمال نوقف التطبيق بسبب الـ intent ده.
    private fun requestIgnoreBatteryOptimizations() {
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
            return
        } catch (e: Exception) {
            // تجاهل ونكمل للـ fallback
        }
        try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            return
        } catch (e: Exception) {
            // تجاهل ونكمل لآخر fallback
        }
        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                }
            )
        } catch (e: Exception) {
            // مفيش fallback تاني — نسيبها بأمان من غير كراش
        }
    }

    private fun isNotificationAccessGranted(): Boolean {
        val pkgName = packageName
        val enabledListeners = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners"
        ) ?: ""
        return enabledListeners.contains(pkgName)
    }

    private fun isSmsPermissionGranted(): Boolean {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.RECEIVE_SMS) ==
            PackageManager.PERMISSION_GRANTED
    }
}
