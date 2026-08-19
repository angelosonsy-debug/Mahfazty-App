import '../models/financial_event.dart';

/// نتيجة وسيطة من الـ Template - الـ SmsParser هو اللي بيجمعها في
/// FinancialEvent كامل (بيضيف id/timestamp/rawMessage/rawSource).
class TemplateExtraction {
  final FinancialSource source;
  final FinancialEventType eventType;
  final double? amount;
  final double? balanceAfter;
  final String? merchant;
  final String? person;
  final String? reference;
  final String? rawDateTimeText;
  final int confidence;

  const TemplateExtraction({
    required this.source,
    required this.eventType,
    required this.confidence,
    this.amount,
    this.balanceAfter,
    this.merchant,
    this.person,
    this.reference,
    this.rawDateTimeText,
  });
}

typedef _Builder = TemplateExtraction Function(RegExpMatch match);

class SmsTemplate {
  final String id;
  final RegExp pattern;
  final _Builder build;

  const SmsTemplate({required this.id, required this.pattern, required this.build});
}

double? _num(String? s) {
  if (s == null) return null;
  return double.tryParse(s.replaceAll(',', '').trim());
}

String? _clean(String? s) => s?.trim();

/// -------------------------------------------------------------------------
/// Vodafone Cash — مصدر: رسائل SMS من "VF-Cash"
/// (نفس الـ Regex اللي اتأكد منها بالمحاكاة قبل كده - من غير تعديل منطقي)
/// -------------------------------------------------------------------------
final List<SmsTemplate> vodafoneCashTemplates = [
  SmsTemplate(
    id: 'vf_payment',
    pattern: RegExp(
      r'تم دفع مبلغ (?<amount>\d+(?:\.\d+)?) جني[ةه] رسوم خدمة لفودافون كاش\.?\s*'
      r'رصيد محفظتك الحالي (?<balance>\d+(?:\.\d+)?) جني[ةه]\.?\s*'
      r'رقم العملية (?<ref>\d+) تاريخ العملية (?<datetime>[\d:\- ]+?)\.',
    ),
    build: (m) => TemplateExtraction(
      source: FinancialSource.vodafoneCash,
      eventType: FinancialEventType.withdrawal,
      amount: _num(m.namedGroup('amount')),
      balanceAfter: _num(m.namedGroup('balance')),
      reference: _clean(m.namedGroup('ref')),
      rawDateTimeText: _clean(m.namedGroup('datetime')),
      confidence: 99,
    ),
  ),
  SmsTemplate(
    id: 'vf_receive',
    pattern: RegExp(
      r'تم استلام مبلغ (?<amount>\d+(?:\.\d+)?) جني[ةه] من رقم (?<senderPhone>\d+) '
      r'المسجل بإسم (?<senderName>.+?) على رقم محفظتك (?<wallet>\d+)\.?\s*'
      r'رصيدك الحالي:?\s*(?<balance>\d+(?:\.\d+)?) جني[ةه]\s*'
      r'تاريخ العملية:?\s*(?<datetime>[\d:\- ]+?)\s*رقم العملية:?\s*(?<ref>\d+)',
    ),
    build: (m) => TemplateExtraction(
      source: FinancialSource.vodafoneCash,
      eventType: FinancialEventType.deposit,
      amount: _num(m.namedGroup('amount')),
      balanceAfter: _num(m.namedGroup('balance')),
      reference: _clean(m.namedGroup('ref')),
      person: _clean(m.namedGroup('senderName')),
      rawDateTimeText: _clean(m.namedGroup('datetime')),
      confidence: 99,
    ),
  ),
  SmsTemplate(
    id: 'vf_withdraw_atm',
    pattern: RegExp(
      r'تم سحب (?<amount>\d+(?:\.\d+)?) جني[ةه] من محفظة فودافون كاش\.?\s*'
      r'رصيد حسابك الحالي (?<balance>\d+(?:\.\d+)?) جني[ةه]\.?\s*'
      r'تاريخ العملية (?<datetime>[\d:\- ]+?) رقم العملية[;:]\s*(?<ref>\d+)',
    ),
    build: (m) => TemplateExtraction(
      source: FinancialSource.vodafoneCash,
      eventType: FinancialEventType.withdrawal,
      amount: _num(m.namedGroup('amount')),
      balanceAfter: _num(m.namedGroup('balance')),
      reference: _clean(m.namedGroup('ref')),
      rawDateTimeText: _clean(m.namedGroup('datetime')),
      confidence: 99,
    ),
  ),
  SmsTemplate(
    id: 'vf_recharge',
    pattern: RegExp(
      r'تم شحن رصيد موبايلك ب (?<rechargeAmount>\d+(?:\.\d+)?) بنجاح وخصم '
      r'(?<amount>\d+(?:\.\d+)?) من محفظتك شاملة الضريبة[;:]?\s*'
      r'رصيد حسابك ف[يى] فودافون كاش الحالي (?<balance>\d+(?:\.\d+)?)',
    ),
    build: (m) => TemplateExtraction(
      source: FinancialSource.vodafoneCash,
      eventType: FinancialEventType.purchase,
      amount: _num(m.namedGroup('amount')),
      balanceAfter: _num(m.namedGroup('balance')),
      merchant: 'شحن رصيد موبايل',
      confidence: 99,
    ),
  ),
  SmsTemplate(
    id: 'vf_transfer_out',
    pattern: RegExp(
      r'تم تحويل (?<amount>\d+(?:\.\d+)?) جني[ةه] لرقم (?<receiverPhone>\d+) '
      r'مصاريف الخدمة (?<fee>\d+(?:\.\d+)?) جني[ةه] رصيد حسابك ف[يى] فودافون كاش '
      r'الحالي (?<balance>\d+(?:\.\d+)?)\.?\s*تاريخ العملية\s*(?<datetime>[\d:\- ]+?)\s*:?\s*'
      r'رقم العملية\s*(?<ref>\d+)',
    ),
    build: (m) => TemplateExtraction(
      source: FinancialSource.vodafoneCash,
      eventType: FinancialEventType.transfer,
      amount: _num(m.namedGroup('amount')),
      balanceAfter: _num(m.namedGroup('balance')),
      reference: _clean(m.namedGroup('ref')),
      person: _clean(m.namedGroup('receiverPhone')),
      rawDateTimeText: _clean(m.namedGroup('datetime')),
      confidence: 99,
    ),
  ),
];

/// -------------------------------------------------------------------------
/// البنك الأهلي (بطاقة مسبقة الدفع) — مصدر: رسائل SMS من "BanK-AlAhly"
/// ملحوظة: مفيهاش رصيد متبقي (balanceAfter) في أي من الرسائل التلاتة -
/// البنك مبيبعتش الرصيد بعد العملية زي فودافون كاش.
/// -------------------------------------------------------------------------
final List<SmsTemplate> alAhlyBankTemplates = [
  SmsTemplate(
    id: 'ahly_transfer_in',
    pattern: RegExp(
      r'تم إضافة تحويل لحظي لبطاقتكم مسبقة الدفع بمبلغ (?<amount>\d+(?:\.\d+)?) جم '
      r'من (?<senderName>.+?) رقم مرجعي (?<ref>\d+) يوم (?<date>[\d\-]+) '
      r'الساعة (?<time>[\d:]+)',
    ),
    build: (m) => TemplateExtraction(
      source: FinancialSource.alAhlyBank,
      eventType: FinancialEventType.deposit,
      amount: _num(m.namedGroup('amount')),
      person: _clean(m.namedGroup('senderName')),
      reference: _clean(m.namedGroup('ref')),
      rawDateTimeText: '${m.namedGroup('date')} ${m.namedGroup('time')}',
      confidence: 99,
    ),
  ),
  SmsTemplate(
    id: 'ahly_card_debit',
    pattern: RegExp(
      r'تم خصم مبلغ (?<amount>\d+(?:\.\d+)?) جم لحظيا باستخدام شبكة المدفوعات '
      r'اللحظية من بطاقتكم \(مسبقة الدفع/المرتبات\) عند (?<merchant>.+?) يوم '
      r'(?<date>[\d\-]+) الساعة (?<time>[\d:]+) مرجع التاجر (?<ref>\d+)',
    ),
    build: (m) => TemplateExtraction(
      source: FinancialSource.alAhlyBank,
      eventType: FinancialEventType.purchase,
      amount: _num(m.namedGroup('amount')),
      merchant: _clean(m.namedGroup('merchant')),
      reference: _clean(m.namedGroup('ref')),
      rawDateTimeText: '${m.namedGroup('date')} ${m.namedGroup('time')}',
      confidence: 99,
    ),
  ),
  SmsTemplate(
    id: 'ahly_transfer_out',
    pattern: RegExp(
      r'تم تنفيذ تحويل لحظي من بطاقتكم مسبقة الدفع بمبلغ (?<amount>\d+(?:\.\d+)?) '
      r'جم إلى (?<receiverName>.+?) رقم مرجعي (?<ref>\d+) يوم (?<date>[\d\-]+) '
      r'الساعة (?<time>[\d:]+)',
    ),
    build: (m) => TemplateExtraction(
      source: FinancialSource.alAhlyBank,
      eventType: FinancialEventType.transfer,
      amount: _num(m.namedGroup('amount')),
      person: _clean(m.namedGroup('receiverName')),
      reference: _clean(m.namedGroup('ref')),
      rawDateTimeText: '${m.namedGroup('date')} ${m.namedGroup('time')}',
      confidence: 99,
    ),
  ),
];
