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
            val time = System.currentTimeMillis()

            // لا ترفض المرسل هنا: قائمة المصادر الديناميكية موجودة في Dart
            // ويجب أن تصل الرسالة إلى SourcePolicy قبل اتخاذ قرار القبول.
            val payload = mapOf(
                "sender" to sender,
                "body" to body,
                "time" to time
            )

            // channel يتقرأ مرة واحدة هنا (مش جوه الـ Handler.post) عشان لو
            // null نقرر نخزّن في الطابور الدائم فورًا - التطبيق ممكن يتقفل
            // قبل ما الـ Handler ينفّذ أصلًا.
            val channel = methodChannel
            if (channel != null) {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    channel.invokeMethod("onSms", payload)
                }
            } else {
                // الـ Flutter engine مش شغال (التطبيق مقفول) - بدل ما
                // الرسالة تتفقد نهائيًا، نخزّنها في طابور دائم على القرص.
                // Dart بيسحبها أول ما التطبيق يفتح تاني (راجع main.dart).
                PendingQueue.enqueueSms(context, sender, body, time)
            }
        }
    }
}
