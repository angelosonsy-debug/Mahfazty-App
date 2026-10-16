/// تطبيع النص قبل أي محاولة Regex:
/// - تحويل الأرقام العربية الهندية / الفارسية لأرقام لاتينية
/// - تجميع أي مسافات/أسطر جديدة متكررة في مسافة واحدة
class TextNormalizer {
  static String normalizeDigits(String input) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const easternArabic = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      final aIndex = arabicIndic.indexOf(char);
      if (aIndex != -1) {
        buffer.write(aIndex.toString());
        continue;
      }
      final eIndex = easternArabic.indexOf(char);
      if (eIndex != -1) {
        buffer.write(eIndex.toString());
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  static String collapseWhitespace(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// تحويل الفواصل العربية للمقابل اللاتيني قبل normalizeDigits.
  /// ٬ (U+066C) = فاصل الآلاف العربي → ','
  /// ٫ (U+066B) = الفاصل العشري العربي → '.'
  static String normalizeSeparators(String input) {
    return input
        .replaceAll('٬', ',')
        .replaceAll('٫', '.');
  }

  static String prepare(String input) {
    return collapseWhitespace(normalizeDigits(normalizeSeparators(input)));
  }
}
