import 'dart:convert';
import 'package:crypto/crypto.dart';

/// مفتاح المستخدم = الاسم (lowercase) + الكود
String userKey(String name, String code) =>
    '${name.trim().toLowerCase()}_${code.trim()}';

/// Firebase Auth بيحتاج إيميل، فبنشتق إيميل ثابت من الاسم + الكود.
/// الهاش بس عشان الإيميل يبقى صالح حتى لو الاسم عربى أو فيه مسافات.
/// (مش سر — الأمان فى كلمة المرور اللى Firebase بيحفظها مشفّرة)
String emailFor(String name, String code) {
  final h = sha256
      .convert(utf8.encode(userKey(name, code)))
      .toString()
      .substring(0, 40);
  return '$h@clinical-pharma.app';
}
