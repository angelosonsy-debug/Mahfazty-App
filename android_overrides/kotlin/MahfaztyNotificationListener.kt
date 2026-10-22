package com.mahfazty.mahfazty

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
        // ده اللي بتوصي بيه توثيق أندرويد الرسمي.
        //
        // الخدمة دي ممكن "تتقفل وتتوصل تاني" من غير ما المستخدم يعمل
        // حاجة — نظام توفير الطاقة (خصوصًا Xiaomi/Oppo/Huawei) بيوقفها
        // أحيانًا وبعدين أندرويد بيعيد تشغيلها. أي إشعار وصل في الفترة
        // دي (الخدمة متوقفة) كان هيضيع تمامًا. الحل: أول ما نتوصل تاني،
        // نجيب كل الإشعارات اللي لسه ظاهرة فعليًا في شريط الإشعارات
        // (getActiveNotifications) ونعالجها زي أي إشعار جديد — نفس
        // المسار بالظبط، صفر تكرار منطق. لو الإشعار الأصلي اتمسح من
        // الشريط قبل ما الخدمة ترجع، للأسف مفيش طريقة نسترجعه (النظام
        // مابيحتفظش بسجل تاريخي للإشعارات المحذوفة لتطبيقات تالتة).
        try {
            for (sbn in activeNotifications) {
                onNotificationPosted(sbn)
            }
        } catch (e: Exception) {
            // تجاهل بأمان - أفضل من كراش يوقف الخدمة كلها تاني
        }
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
