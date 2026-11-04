package com.mahfazty.mahfazty

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import io.flutter.plugin.common.MethodChannel

class SmsReceiver : BroadcastReceiver() {

    companion object {
        // بيتحط من MainActivity لما الـ Flutter engine يبدأ
        var methodChannel: MethodChannel? = null

    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        for (message in messages) {
            val sender = message.originatingAddress ?: continue
            val body = message.messageBody ?: continue

            // لا ترفض المرسل هنا: قائمة المصادر الديناميكية موجودة في Dart
            // ويجب أن تصل الرسالة إلى SourcePolicy قبل اتخاذ قرار القبول.
            val payload = mapOf(
                "sender" to sender,
                "body" to body,
                "time" to System.currentTimeMillis()
            )

            // MethodChannel لازم يتنادى على الـ main thread
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                methodChannel?.invokeMethod("onSms", payload)
            }
        }
    }
}
