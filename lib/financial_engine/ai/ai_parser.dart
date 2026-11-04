import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/financial_event.dart';

/// نتيجة فهم الـ AI للرسالة - طبقة مستقلة تمامًا عن الـ Parser القاعدي
/// (Rule Engine). الـ AI بقى المفسّر الأساسي للرسالة لما يكون متاح
/// (مفتاح متحط ومفعّل)؛ الـ Rule Engine بيشتغل بس لما الـ AI مش متاح -
/// (مفيش مفتاح، متقفل، أو فشل الاتصال) عشان التطبيق يفضل شغال أوفلاين.
/// القرار النهائي لتطبيق أي حدث لسه بيمر عبر FinancialEngine بس.
class AiParseResult {
  final bool isFinancial;
  final bool isPromotional;
  final bool shouldIgnore;
  final FinancialEventType? eventType;
  final double? amount;
  final double? remainingBalance;
  final String? wallet;
  final String? provider;
  final String? senderName;
  final String? receiverName;
  final int confidence; // 0-100

  const AiParseResult({
    required this.isFinancial,
    required this.isPromotional,
    required this.shouldIgnore,
    required this.confidence,
    this.eventType,
    this.amount,
    this.remainingBalance,
    this.wallet,
    this.provider,
    this.senderName,
    this.receiverName,
  });
}

class AiParser {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-haiku-4-5-20251001'; // موديل خفيف وسريع ورخيص، مناسب لتصنيف نص قصير

  /// بيبعت نص الإشعار/الرسالة بس (من غير أي بيانات تانية) للـ AI باستخدام
  /// مفتاح المستخدم نفسه، وبيرجع تفسير منظم أو null لو أي مشكلة حصلت
  /// (مفتاح غلط، مفيش إنترنت، رد غير متوقع...) - أي فشل هنا لازم يخلي
  /// التطبيق يكمل بمنطق القواعد (Rule Engine) بدل ما يوقف أو يكسر.
  static Future<AiParseResult?> analyze(String rawMessage, {required String apiKey}) async {
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'max_tokens': 400,
              'messages': [
                {'role': 'user', 'content': _buildPrompt(rawMessage)},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final content = decoded['content'] as List?;
      if (content == null || content.isEmpty) return null;
      final text = (content.first as Map)['text'] as String?;
      if (text == null) return null;

      return parseModelReply(text);
    } catch (_) {
      return null;
    }
  }

  /// منطق تفسير رد الموديل - مفصول عمدًا عن الاتصال بالشبكة عشان نقدر
  /// نختبره مباشرة بأمثلة نصية من غير ما نحتاج نعمل Mock لـ HTTP.
  static AiParseResult? parseModelReply(String text) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch == null) return null;
      final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;

      FinancialEventType? type;
      final typeStr = parsed['transactionType'] as String?;
      if (typeStr == 'deposit') type = FinancialEventType.deposit;
      if (typeStr == 'withdrawal') type = FinancialEventType.withdrawal;

      final amount = (parsed['amount'] as num?)?.toDouble();
      final remainingBalance = (parsed['remainingBalance'] as num?)?.toDouble();
      final wallet = parsed['wallet'] as String?;
      final provider = parsed['provider'] as String?;
      final senderName = parsed['sender'] as String?;
      final receiverName = parsed['receiver'] as String?;
      final isFinancial = parsed['isFinancial'] as bool? ?? (type != null || amount != null);
      final isPromotional = parsed['isPromotional'] as bool? ?? false;
      final shouldIgnore = parsed['shouldIgnore'] as bool? ?? false;

      final rawConfidence = (parsed['confidence'] as num?)?.toDouble() ?? 0;
      // الموديل ممكن يرجع 0-1 أو 0-100 حسب فهمه للبرومبت - بنطبّع لـ 0-100
      final normalized = rawConfidence <= 1 ? (rawConfidence * 100).round() : rawConfidence.round();

      return AiParseResult(
        isFinancial: isFinancial,
        isPromotional: isPromotional,
        shouldIgnore: shouldIgnore,
        eventType: type,
        amount: amount,
        remainingBalance: remainingBalance,
        wallet: (wallet != null && wallet != 'unknown') ? wallet : null,
        provider: (provider != null && provider != 'unknown') ? provider : null,
        senderName: (senderName != null && senderName != 'unknown') ? senderName : null,
        receiverName: (receiverName != null && receiverName != 'unknown') ? receiverName : null,
        confidence: normalized.clamp(0, 100),
      );
    } catch (_) {
      return null;
    }
  }

  static String _buildPrompt(String rawMessage) {
    return '''أنت محلل رسائل مالية مصري. حلل نص الإشعار/الرسالة دي بدقة، واستخرج كل
حاجة تقدر تستخرجها منها. ارجع JSON بس من غير أي نص إضافي ولا Markdown،
بالشكل ده بالظبط:

{
  "isFinancial": true أو false (هل الرسالة دي معاملة مالية أصلاً؟),
  "isPromotional": true أو false (عرض/إعلان/تسويق؟),
  "shouldIgnore": true أو false (لو ترويجية أو مش مالية، خليها true),
  "transactionType": "deposit" أو "withdrawal" أو "unknown",
  "amount": رقم المعاملة أو null,
  "remainingBalance": الرصيد المتبقي بعد العملية لو مذكور، أو null,
  "wallet": "Vodafone Cash" أو "InstaPay" أو "unknown",
  "provider": اسم مزوّد الخدمة/البنك لو واضح (مثلاً "البنك الأهلي") أو "unknown",
  "sender": اسم/رقم المُرسل لو مذكور في نص الرسالة نفسه أو "unknown",
  "receiver": اسم/رقم المستلم لو مذكور في نص الرسالة نفسه أو "unknown",
  "confidence": رقم من 0 لـ 100 يعبّر عن ثقتك في التفسير ده
}

كن دقيق جدًا في استخراج المبلغ والرصيد المتبقي - دي أهم حاجة. لو مش
متأكد من حاجة، حطها "unknown" أو null بدل ما تخمّن.

النص:
"""
$rawMessage
"""''';
  }
}
