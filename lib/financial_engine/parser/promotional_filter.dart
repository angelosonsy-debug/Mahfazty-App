import '../../core/utils/text_normalizer.dart';

/// أي رسالة/إشعار ترويجي أو عرض أو تحديث نظام - مش معاملة مالية خالص.
/// لازم يتجاهل تمامًا (مايوصلش لـ FinancialEngine ولا يظهر في Inbox).
class PromotionalFilter {
  static final List<String> _promotionalKeywords = [
    // عربي
    'عرض خاص', 'عرض حصري', 'اشترك الآن', 'جدد باقتك', 'باقة جديدة',
    'خصم يصل', 'اطلب الآن', 'لفترة محدودة', 'العرض ساري', 'كود الخصم',
    'اشحن رصيدك واحصل', 'مكالمات مجانية', 'انترنت مجاني', 'هدية منك',
    // English
    'special offer', 'limited time', 'subscribe now', 'discount code',
    'promo code', 'free minutes', 'renew your plan', 'exclusive offer',
    // إشعارات نظام غير مالية
    'الشحن', 'battery', 'شاحن', 'تحديث', 'update available',
    'تنزيل', 'downloading', 'تقويم', 'calendar',
  ];

  static bool isPromotional(String text) {
    final normalized = TextNormalizer.prepare(text).toLowerCase();
    return _promotionalKeywords.any((k) => normalized.contains(k.toLowerCase()));
  }
}
