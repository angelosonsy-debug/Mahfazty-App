import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/financial_event.dart';

/// نتيجة تحليل الـ AI من الـ backend proxy.
class AiAnalysisResult {
  final bool isFinancial;
  final FinancialEventType? direction; // null = UNKNOWN
  final double? amount;
  final double confidence;          // 0.0 - 1.0
  final String? explanation;

  const AiAnalysisResult({
    required this.isFinancial,
    required this.direction,
    required this.amount,
    required this.confidence,
    required this.explanation,
  });
}

/// C3 — Client آمن للـ AI proxy.
///
/// المستخدم لا يرى API key ولا يتفاعل مع أي مزود AI مباشرة.
/// الـ endpoint URL مضبوط من مكان واحد فقط.
class AiBackendClient {
  AiBackendClient({http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  static const _endpointUrl = String.fromEnvironment(
    'MAHFAZTY_AI_PROXY_URL',
    defaultValue: 'https://mahfazty-ai-proxy.your-subdomain.workers.dev/parse',
  );

  /// مهلة انتظار الـ proxy — أقصر من مهلة الـ Worker لتحاشي تعليق التطبيق.
  static const _timeout = Duration(seconds: 10);

  /// حد أقصى لحجم النص المرسل (5KB) — يطابق حد الـ Worker.
  static const _maxTextBytes = 5 * 1024;

  final http.Client _client;

  /// طلب تحليل رسالة واحدة من الـ AI proxy.
  ///
  /// يرجع null في كل حالات الفشل (timeout، network error، invalid response،
  /// وغيرها) حتى لا يتوقف التطبيق على الـ AI.
  Future<AiAnalysisResult?> analyze({
    required String source,
    required String text,
    required bool isSms,
  }) async {
    // حماية: لو النص كبير جدًا نرفضه محليًا قبل الإرسال
    final textBytes = utf8.encode(text);
    if (textBytes.length > _maxTextBytes) return null;

    final body = jsonEncode({
      'source': source,
      'text': text,
      'context': {'sourceType': isSms ? 'sms' : 'notification'},
    });

    try {
      final response = await _client
          .post(
            Uri.parse(_endpointUrl),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode == 429) return null;  // rate limited
      if (response.statusCode != 200) return null;  // server error

      return _parseResponse(response.body);
    } on TimeoutException {
      return null; // timeout
    } on SocketException {
      return null; // offline
    } catch (_) {
      return null; // أي خطأ آخر (HttpException وغيره) — آمن
    }
  }

  AiAnalysisResult? _parseResponse(String rawBody) {
    try {
      final json = jsonDecode(rawBody) as Map<String, dynamic>;

      final isFinancial = json['isFinancial'] as bool?;
      if (isFinancial == null) return null;

      final directionStr = json['direction'] as String?;
      FinancialEventType? direction;
      switch (directionStr) {
        case 'DEBIT':
          direction = FinancialEventType.withdrawal;
        case 'CREDIT':
          direction = FinancialEventType.deposit;
        case null:
          direction = null; // field absent — unknown, acceptable
        default:
          return null; // present but unrecognised string — reject response
      }

      // Validate amount
      double? amount;
      final rawAmount = json['amount'];
      if (rawAmount != null) {
        if (rawAmount is num) {
          final d = rawAmount.toDouble();
          if (d > 0 && d.isFinite) amount = d;
        }
        // لو مش رقم موجب صالح → نتجاهله (null)
      }

      // Validate confidence
      final rawConf = json['confidence'];
      if (rawConf is! num) return null;
      final confidence = rawConf.toDouble().clamp(0.0, 1.0);

      final explanation = json['explanation'] is String
          ? (json['explanation'] as String).trim()
          : null;

      return AiAnalysisResult(
        isFinancial: isFinancial,
        direction: direction,
        amount: amount,
        confidence: confidence,
        explanation: explanation.isEmptyOrNull ? null : explanation,
      );
    } catch (_) {
      return null; // malformed JSON → safe fallback
    }
  }
}

extension _StringNullable on String? {
  bool get isEmptyOrNull => this == null || this!.isEmpty;
}
