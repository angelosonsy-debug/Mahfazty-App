package com.mahfazty.trial

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import io.flutter.plugin.common.MethodChannel

class SmsReceiver : BroadcastReceiver() {

    companion object {
        // بيتحط من MainActivity لما الـ Flutter engine يبدأ
        var methodChannel: MethodChannel? = null

        // المصادر المعروفة بس - أي حاجة تانية نتجاهلها تمامًا
        private val KNOWN_SENDER_KEYWORDS = listOf("vf-cash", "vfcash", "vodafone", "ahly", "alahly")
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        for (message in messages) {
            val sender = message.originatingAddress ?: continue
            val body = message.messageBody ?: continue

            val senderLower = sender.lowercase()
            val isKnownSource = KNOWN_SENDER_KEYWORDS.any { senderLower.contains(it) }
            if (!isKnownSource) continue // نتجاهل أي رسالة من مصدر غير معروف

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
