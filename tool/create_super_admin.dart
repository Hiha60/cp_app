// أداة لمرة واحدة: بتنشئ حساب Firebase Auth لأول Super Admin وبتطبعلك الـ uid
// والـ JSON اللى تلصقه فى Firestore Console.
//
// ليه يدويًا؟ لأن قواعد Firestore (عن قصد) بتمنع أى حد من إنشاء super_admin
// من التطبيق، فالأول بيتعمل مرة واحدة من الـ Console.
//
// الاستخدام (من فولدر المشروع):
//   dart run tool/create_super_admin.dart <API_KEY> <name> <4-digit-code> <password>
//
// الـ API_KEY هو Web API Key من Firebase Console → Project Settings.
// ملحوظة: الإيميل المشتق لازم يطابق emailFor() فى lib/core/utils/identity.dart.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:cp_app/core/utils/identity.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    stderr.writeln(
        'Usage: dart run tool/create_super_admin.dart <API_KEY> <name> <4-digit-code> <password>');
    exit(64);
  }
  final apiKey = args[0], name = args[1], code = args[2], password = args[3];

  if (!RegExp(r'^\d{4}$').hasMatch(code)) {
    stderr.writeln('الكود لازم يكون 4 أرقام');
    exit(64);
  }
  if (password.length < 8) {
    stderr.writeln('كلمة المرور لازم تكون 8 خانات على الأقل');
    exit(64);
  }

  final email = emailFor(name, code);
  final res = await http.post(
    Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(
        {'email': email, 'password': password, 'returnSecureToken': false}),
  );

  if (res.statusCode != 200) {
    stderr.writeln('فشل إنشاء الحساب: ${res.body}');
    exit(1);
  }
  final uid = (jsonDecode(res.body) as Map<String, dynamic>)['localId'];

  stdout.writeln('''
✅ اتعمل حساب Firebase Auth.

UID: $uid

دلوقتى افتح Firebase Console → Firestore Database → Start collection (أو افتح users):
  Collection ID : users
  Document ID   : $uid
  الحقول:
    name           (string)  : $name
    code           (string)  : $code
    role           (string)  : super_admin
    hospital_id    (string)  : ""        <- سيبه فاضى لو السوبر أدمن مالوش مستشفى
    department_ids (array)   : []
    active         (boolean) : true

بعد كده سجّل دخول بالاسم والكود والباسورد، ومن تاب "المستشفيات" أضف المستشفيات والمدراء.
''');
}
