package com.mahfazty.trial

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.MethodChannel

class MahfaztyNotificationListener : NotificationListenerService() {

    companion object {
        // بيتحط من MainActivity لما الـ Flutter engine يبدأ
        var methodChannel: MethodChannel? = null
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        // النظام لازم يأكد إن الخدمة اتوصلت قبل ما نعتمد عليها -
        // ده اللي بتوصي بيه توثيق أندرويد الرسمي
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        super.onNotificationPosted(sbn)

        val extras: android.os.Bundle = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        if (title.isEmpty() && text.isEmpty()) return

        val payload = mapOf(
            "packageName" to sbn.packageName,
            "title" to title,
            "text" to text,
            "time" to sbn.postTime
        )

        android.os.Handler(android.os.Looper.getMainLooper()).post {
            methodChannel?.invokeMethod("onNotification", payload)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        super.onNotificationRemoved(sbn)
    }
}
