import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// استثناء خاص بعمليات Google Drive — بديل لاستخدام http.ClientException
/// (المفروض تبقى للأخطاء على مستوى الشبكة نفسها، مش أخطاء الـ API).
class GoogleDriveBackupException implements Exception {
  final String message;
  const GoogleDriveBackupException(this.message);
  @override
  String toString() => message;
}

class _DriveFileMeta {
  final String id;
  final DateTime modifiedTime;
  const _DriveFileMeta({required this.id, required this.modifiedTime});
}

/// نسخ احتياطي سحابي عبر appDataFolder الخاص بالتطبيق في Google Drive
/// بتاع المستخدم. appDataFolder مساحة مخفية بالكامل عن واجهة Drive
/// العادية وعن أي تطبيق تاني — التطبيق بتاعنا بس (بنفس الـ OAuth Client)
/// يقدر يوصلها، وده المبرر اللي بيخلي نطاق drive.appdata كافي تمامًا
/// (مش محتاجين drive.file ولا نطاق Drive الكامل أبدًا).
///
/// بنستخدم REST API مباشرة عبر http (موجودة بالفعل كـ dependency) بدل
/// إضافة مكتبة googleapis الكبيرة — نفس الفلسفة اللي BackupService
/// بيتبعها: أقل أسطح Gradle/مكتبات ممكنة.
class GoogleDriveBackupService {
  static const _backupFileName = 'mahfazty_backup.json';
  static const _driveFilesUrl = 'https://www.googleapis.com/drive/v3/files';
  static const _driveUploadUrl = 'https://www.googleapis.com/upload/drive/v3/files';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['https://www.googleapis.com/auth/drive.appdata'],
  );

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  /// بيجرّب silent sign-in لو فيه جلسة محفوظة من قبل — من غير ما يفتح
  /// أي واجهة للمستخدم. ده اللي بيخلي isSignedIn() آمنة تُستدعى عند فتح
  /// التطبيق (main.dart._maybeBackupOnOpen) من غير تفاعل مباشر.
  Future<bool> isSignedIn() async {
    if (_googleSignIn.currentUser != null) return true;
    try {
      final account = await _googleSignIn.signInSilently();
      return account != null;
    } catch (_) {
      return false;
    }
  }

  /// بيفتح واجهة اختيار الحساب — لازم يتصل من تفاعل مباشر للمستخدم
  /// (ضغطة زرار)، مش من الخلفية.
  Future<GoogleSignInAccount?> signIn() => _googleSignIn.signIn();

  Future<void> signOut() => _googleSignIn.signOut();

  Future<Map<String, String>> _authHeaders() async {
    final account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
    if (account == null) {
      throw const GoogleDriveBackupException('مفيش حساب Google مسجّل دخول');
    }
    return account.authHeaders;
  }

  /// بيدوّر على ملف النسخة الاحتياطية جوه appDataFolder. بيرجع null لو
  /// مفيش (أول مرة)، أو لو الاستعلام فشل بسبب شبكة/صلاحية (نتعامل معاه
  /// كـ "مفيش نسخة لسه" بدل ما نكسر التدفق كله على فشل مؤقت).
  Future<_DriveFileMeta?> _findBackupFile() async {
    final headers = await _authHeaders();
    final uri = Uri.parse(_driveFilesUrl).replace(queryParameters: {
      'spaces': 'appDataFolder',
      'q': "name='$_backupFileName' and trashed=false",
      'fields': 'files(id,modifiedTime)',
      'pageSize': '1',
    });
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw GoogleDriveBackupException('فشل البحث عن النسخة الاحتياطية (${response.statusCode})');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final files = decoded['files'] as List?;
    if (files == null || files.isEmpty) return null;
    final first = files.first as Map<String, dynamic>;
    return _DriveFileMeta(
      id: first['id'] as String,
      modifiedTime: DateTime.parse(first['modifiedTime'] as String),
    );
  }

  Future<bool> hasExistingBackup() async {
    final meta = await _findBackupFile();
    return meta != null;
  }

  /// بيُقرأ من metadata الملف نفسه على Drive (modifiedTime) — مفيش
  /// تخزين محلي منفصل للتاريخ، عشان نتجنب أي تضارب بين "آخر نسخة فعلية
  /// موجودة على Drive" و"آخر وقت اتسجل محليًا" لو حصل فشل جزئي في الرفع
  /// (مثلاً الشبكة قُطعت بعد ما سجّلنا النجاح محليًا بس قبل ما يوصل فعليًا).
  Future<DateTime?> getLastBackupTimestamp() async {
    final meta = await _findBackupFile();
    return meta?.modifiedTime;
  }

  /// بيرفع/يستبدل النسخة بالكامل (overwrite، بدون سجل إصدارات). لو فيه
  /// ملف موجود بالفعل بيتعمله PATCH (نفس الـ fileId)، لو مفيش بيتعمل
  /// POST (إنشاء جديد).
  Future<void> uploadBackup(String jsonData) async {
    final headers = await _authHeaders();
    final existing = await _findBackupFile();

    final metadata = existing == null
        ? {
            'name': _backupFileName,
            'parents': ['appDataFolder'],
          }
        : <String, dynamic>{}; // التحديث مابيحتاجش يعيد تحديد الاسم/الأب

    const boundary = '-------mahfazty-backup-boundary';
    final body = StringBuffer()
      ..write('--$boundary\r\n')
      ..write('Content-Type: application/json; charset=UTF-8\r\n\r\n')
      ..write(jsonEncode(metadata))
      ..write('\r\n--$boundary\r\n')
      ..write('Content-Type: application/json\r\n\r\n')
      ..write(jsonData)
      ..write('\r\n--$boundary--');

    final uri = existing == null
        ? Uri.parse('$_driveUploadUrl?uploadType=multipart')
        : Uri.parse('$_driveUploadUrl/${existing.id}?uploadType=multipart');

    final request = http.Request(existing == null ? 'POST' : 'PATCH', uri);
    request.headers.addAll(headers);
    request.headers['Content-Type'] = 'multipart/related; boundary=$boundary';
    request.body = body.toString();

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw GoogleDriveBackupException('فشل رفع النسخة الاحتياطية (${response.statusCode})');
    }
  }

  /// بيرجع محتوى آخر نسخة، أو null لو مفيش نسخة سابقة (أول استخدام).
  Future<String?> downloadBackup() async {
    final meta = await _findBackupFile();
    if (meta == null) return null;
    final headers = await _authHeaders();
    final uri = Uri.parse('$_driveFilesUrl/${meta.id}').replace(
      queryParameters: {'alt': 'media'},
    );
    final response = await http.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw GoogleDriveBackupException('فشل تحميل النسخة الاحتياطية (${response.statusCode})');
    }
    return response.body;
  }
}
