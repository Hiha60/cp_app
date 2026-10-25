import '../../core/utils/identity.dart';
import '../models/user_model.dart';
import 'firebase_rest_service.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository._();
  static final instance = AuthRepository._();

  final _rest = FirebaseRestService.instance;

  // ── Login (Firebase Auth حقيقى) ───────────────────────────────────────
  Future<UserModel> login({
    required String name,
    required String code,
    required String password,
  }) async {
    try {
      await _rest.signIn(emailFor(name, code), password);
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
    final user = await _profile(_rest.uid!);
    if (user == null || !user.active) {
      _rest.signOut();
      throw const AuthException('الحساب غير موجود أو معطّل. تواصل مع المدير');
    }
    return user;
  }

  /// استرجاع الجلسة من refresh token. بيرجّع null لو الجلسة مبقتش صالحة.
  Future<UserModel?> restoreSession(String refreshToken) async {
    try {
      await _rest.restore(refreshToken);
    } on ApiException {
      return null;
    }
    final user = await _profile(_rest.uid!);
    if (user == null || !user.active) {
      _rest.signOut();
      return null;
    }
    return user;
  }

  Future<UserModel?> _profile(String uid) async {
    try {
      return await fetchUser(uid);
    } on ApiException catch (e) {
      // الحساب معطّل أو مالوش مستند → القواعد بترفض القراءة
      if (e.isPermissionDenied) return null;
      rethrow;
    }
  }

  // ── Fetch User ────────────────────────────────────────────────────────
  Future<UserModel?> fetchUser(String uid) async {
    final doc = await _rest.getDoc('users/$uid');
    if (doc == null) return null;
    return UserModel.fromMap(uid, FirebaseRestService.docData(doc));
  }

  // ── Fetch Users by Hospital ───────────────────────────────────────────
  Future<List<UserModel>> fetchUsersByHospital(String hospitalId) async {
    final docs = await _rest.listDocs('users', where: {'hospital_id': hospitalId});
    return docs
        .map((d) => UserModel.fromMap(
              FirebaseRestService.docId(d),
              FirebaseRestService.docData(d),
            ))
        .toList();
  }

  // ── إنشاء حساب Auth (مع استرجاع حساب يتيم من محاولة فاشلة سابقة) ────
  /// لو الحساب اتعمل قبل كده فى محاولة فشلت قبل كتابة المستند، ونفس الباسورد
  /// اتدخل تانى، بنكمل بنفس الـ uid بدل ما الاسم+الكود يتقفلوا للأبد.
  Future<String> registerAccount({
    required String name,
    required String code,
    required String password,
  }) async {
    final email = emailFor(name, code);
    try {
      return await _rest.createAuthAccount(email, password);
    } on ApiException catch (e) {
      if (e.code == 'EMAIL_EXISTS') {
        try {
          return await _rest.verifyCredentials(email, password);
        } on ApiException {
          throw const AuthException('الاسم + الكود مستخدمين بالفعل');
        }
      }
      throw AuthException(e.message);
    }
  }

  // ── Create User (المدير / السوبر أدمن) ────────────────────────────────
  /// الصلاحيات الحقيقية (مين يقدر ينشئ أى دور) بتتفرض فى firestore.rules.
  Future<String> createUser({
    required String name,
    required String code,
    required String password,
    required String role,
    required String hospitalId,
    List<String> departmentIds = const [],
  }) async {
    final uid = await registerAccount(name: name, code: code, password: password);
    try {
      await _rest.commit([
        WriteOp.set(
          'users/$uid',
          {
            'name': name.trim(),
            'code': code.trim(),
            'role': role,
            'hospital_id': hospitalId,
            'department_ids': departmentIds,
            'active': true,
            'created_by': _rest.uid,
          },
          serverTimeFields: const ['created_at'],
          createOnly: true,
        ),
      ]);
    } on ApiException catch (e) {
      if (e.isPermissionDenied || e.status == 409) {
        throw const AuthException(
            'تعذّر إنشاء المستخدم: موجود بالفعل أو لا تملك الصلاحية');
      }
      rethrow;
    }
    return uid;
  }

  // ── تعطيل مستخدم (بدل الحذف) ──────────────────────────────────────────
  /// Firebase Auth مينفعش نحذف منه من التطبيق من غير سيرفر، فبنعطّل المستخدم.
  /// القواعد بترفض أى قراءة/كتابة لحساب active=false فورًا.
  Future<void> deactivateUser(String uid) =>
      _rest.updateDoc('users/$uid', {'active': false});

  // ── تغيير كلمة المرور (للمستخدم نفسه) ─────────────────────────────────
  Future<void> changeOwnPassword({
    required UserModel user,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      // دخول جديد بالباسورد الحالى (بيأكده، وFirebase بيطلب دخول حديث لتغيير الباسورد)
      await _rest.signIn(emailFor(user.name, user.code), currentPassword);
      await _rest.changePassword(newPassword);
    } on ApiException catch (e) {
      throw AuthException(e.message);
    }
  }
}
