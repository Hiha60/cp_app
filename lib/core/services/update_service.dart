import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateStatus {
  final bool mustUpdate;
  final String? url, message, latest;
  const UpdateStatus({
    this.mustUpdate = false,
    this.url,
    this.message,
    this.latest,
  });
}

class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  // ⚠️ بدّل VERSION_JSON_ID بالـ ID بتاع ملف version.json على درايف
  static const _versionJsonUrl =
      'https://drive.google.com/uc?export=download&id=1GoTS7j9dmBK1dFlT7zlLkQKT0fUt0DQx';

  // true  = لو مفيش نت أو الفحص فشل يتقفل البرنامج
  // false = يسمح بالدخول (الأفضل لأن الصيادلة ممكن يكونوا أوفلاين)
  static const _blockWhenOffline = false;

  Future<UpdateStatus> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final res = await http
          .get(Uri.parse(
              '$_versionJsonUrl&t=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) throw Exception('bad status ${res.statusCode}');

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final minV = data['min_version'] as String;
      final url = Platform.isAndroid
          ? data['android_url'] as String?
          : data['windows_url'] as String?;

      return UpdateStatus(
        mustUpdate: _isLower(info.version, minV),
        url: url,
        latest: data['latest_version'] as String?,
        message: data['message'] as String?,
      );
    } catch (_) {
      if (_blockWhenOffline) {
        return const UpdateStatus(
          mustUpdate: true,
          message: 'تعذر التحقق من الإصدار، تأكد من الاتصال بالإنترنت',
        );
      }
      return const UpdateStatus();
    }
  }

  // true لو a أقل من b  (مثال: 1.0.0 < 1.2.0)
  bool _isLower(String a, String b) {
    final x = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final y = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final p = i < x.length ? x[i] : 0;
      final q = i < y.length ? y[i] : 0;
      if (p != q) return p < q;
    }
    return false;
  }
}
