package com.mahfazty.mahfazty

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/// طابور دائم بسيط (SharedPreferences + JSON، بدون أي مكتبة إضافية) —
/// الهدف الوحيد منه: لو SMS أو إشعار وصل والـ Flutter engine مش شغال
/// (التطبيق مقفول تمامًا، methodChannel == null في SmsReceiver/
/// MahfaztyNotificationListener)، نخزّنه هنا بدل ما يتفقد نهائيًا. أول
/// ما التطبيق يفتح تاني، Dart بيسحب كل حاجة متراكمة (drainSms/
/// drainNotifications) ويعالجها بنفس مسار المعالجة العادي بالظبط.
///
/// قرار تصميم مهم: السحب (drain) بيمسح الطابور فورًا، قبل ما Dart يخلص
/// معالجة العناصر. يعني لو حصل كراش في Flutter بالظبط في اللحظة دي،
/// العناصر دي بتضيع (نادر جدًا). البديل (نسيب العناصر لحد ما Dart يأكد
/// المعالجة) كان هيعرّضنا لخطر أكبر بكتير: تكرار نفس المعاملة المالية
/// مرتين لو حصل كراش بعد المعالجة وقبل التأكيد. تكرار معاملة مالية أخطر
/// من فقدان نادر جدًا، فده تريد-أوف مقصود.
object PendingQueue {
    private const val PREFS_NAME = "mahfazty_pending_queue"
    private const val SMS_KEY = "pending_sms"
    private const val NOTIFICATIONS_KEY = "pending_notifications"

    // حد أقصى لمنع نمو غير محدود لو التطبيق فضل مقفول تمامًا لفترة طويلة
    // جدًا (أسابيع). بنسيب الأحدث فقط لو اتعدى الحد - أفضل من استهلاك
    // مساحة غير محدودة.
    private const val MAX_QUEUE_SIZE = 500

    @Synchronized
    fun enqueueSms(context: Context, sender: String, body: String, time: Long) {
        val item = JSONObject().apply {
            put("sender", sender)
            put("body", body)
            put("time", time)
        }
        append(context, SMS_KEY, item)
    }

    @Synchronized
    fun enqueueNotification(context: Context, packageName: String, title: String, text: String, time: Long) {
        val item = JSONObject().apply {
            put("packageName", packageName)
            put("title", title)
            put("text", text)
            put("time", time)
        }
        append(context, NOTIFICATIONS_KEY, item)
    }

    @Synchronized
    fun drainSms(context: Context): List<Map<String, Any?>> = drain(context, SMS_KEY)

    @Synchronized
    fun drainNotifications(context: Context): List<Map<String, Any?>> = drain(context, NOTIFICATIONS_KEY)

    private fun append(context: Context, key: String, item: JSONObject) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val array = JSONArray(prefs.getString(key, "[]"))
        array.put(item)
        val trimmed = if (array.length() > MAX_QUEUE_SIZE) {
            val start = array.length() - MAX_QUEUE_SIZE
            val newArray = JSONArray()
            for (i in start until array.length()) newArray.put(array.get(i))
            newArray
        } else {
            array
        }
        // commit() مش apply(): لازم نضمن الكتابة خلصت فعليًا على القرص قبل
        // ما onReceive/onNotificationPosted يرجع - الـ BroadcastReceiver
        // ممكن يتقفل خلال ثواني من النظام، وapply() غير متزامن (ممكن
        // يتقفل العملية قبل ما تتنفذ فعليًا).
        prefs.edit().putString(key, trimmed.toString()).commit()
    }

    private fun drain(context: Context, key: String): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val array = JSONArray(prefs.getString(key, "[]"))
        val result = mutableListOf<Map<String, Any?>>()
        for (i in 0 until array.length()) {
            val obj = array.getJSONObject(i)
            val map = mutableMapOf<String, Any?>()
            val keys = obj.keys()
            for (k in keys) map[k] = obj.get(k)
            result.add(map)
        }
        prefs.edit().putString(key, "[]").commit()
        return result
    }
}
