import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/firebase_rest_service.dart';
import '../../../data/repositories/org_repository.dart';
import '../../patients/controllers/patients_controller.dart';

/// تخزين آمن لـ refresh token (Keychain / Keystore / Windows Credential Locker).
/// لو التخزين الآمن مش متاح على الجهاز، التطبيق يشتغل عادى بس من غير "تذكرنى".
class _SessionStore {
  static const _key = 'refresh_token';
  final _s = const FlutterSecureStorage();

  Future<String?> read() async {
    try {
      return await _s.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String v) async {
    try {
      await _s.write(key: _key, value: v);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _s.delete(key: _key);
    } catch (_) {}
  }
}

class AuthController extends GetxController {
  static AuthController get to => Get.find();

  final _store = _SessionStore();
  final _rest = FirebaseRestService.instance;

  // ── Fields ──────────────────────────────────────────────────────────
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final isLoading = false.obs;
  final showPassword = false.obs;
  final errorMsg = ''.obs;

  // المستخدم الحالى — null = لم يسجّل الدخول
  final Rx<UserModel?> currentUser = Rx<UserModel?>(null);

  // ── Getters ─────────────────────────────────────────────────────────
  bool get isLoggedIn => currentUser.value != null;
  UserModel get user => currentUser.value!;

  // ── Init ─────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    // اتشال _restoreSession() من هنا — الـ splash هو اللي بيناديها
    _rest.onSessionExpired = () {
      if (isLoggedIn) {
        Get.snackbar('انتهت الجلسة', 'سجّل الدخول من جديد');
        logout();
      }
    };
  }

  @override
  void onClose() {
    nameCtrl.dispose();
    codeCtrl.dispose();
    passwordCtrl.dispose();
    super.onClose();
  }

  // ── Restore Session ─────────────────────────────────────────────────
  /// بترجع true لو في session صالحة (من غير ما تعمل navigate)
  Future<bool> restoreSession() async {
    final token = await _store.read();
    if (token == null) return false;

    UserModel? user;
    try {
      user = await AuthRepository.instance.restoreSession(token);
    } catch (_) {
      return false; // مفيش إنترنت مثلاً — يفضل فى شاشة الدخول وما نمسحش التوكن
    }
    if (user == null) {
      await _store.clear();
      return false;
    }
    await _onAuthenticatedWithoutNavigation(user);
    return true;
  }

  // ── Login ────────────────────────────────────────────────────────────
  Future<void> login() async {
    errorMsg.value = '';
    if (!formKey.currentState!.validate()) return;

    isLoading.value = true;
    try {
      final user = await AuthRepository.instance.login(
        name: nameCtrl.text.trim(),
        code: codeCtrl.text.trim(),
        password: passwordCtrl.text,
      );
      passwordCtrl.clear();
      await _onAuthenticated(user);
    } on AuthException catch (e) {
      errorMsg.value = e.message;
    } on ApiException catch (e) {
      errorMsg.value = e.message;
    } catch (_) {
      errorMsg.value = 'تعذّر الاتصال. تأكد من الإنترنت وحاول مرة تانية';
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _onAuthenticated(UserModel user) async {
    await _onAuthenticatedWithoutNavigation(user);
    _navigateHome();
  }

  Future<void> _onAuthenticatedWithoutNavigation(UserModel user) async {
    currentUser.value = user;
    final rt = _rest.refreshToken;
    if (rt != null) await _store.write(rt);

    // الصيدلانى: لو طلب تغيير قسمه عدّى 24 ساعة بدون رد، يتطبق دلوقتى
    if (user.isPharmacist) {
      try {
        if (await OrgRepository.instance.applyMyExpired(user.id)) {
          await refreshUser();
        }
      } catch (_) {}
    }
  }

  // ── Refresh current user (بعد تغيير القسم مثلاً) ─────────────────────
  Future<void> refreshUser() async {
    if (!isLoggedIn) return;
    final u = await AuthRepository.instance.fetchUser(user.id);
    if (u != null) currentUser.value = u;
  }

  // ── Change password ──────────────────────────────────────────────────
  Future<void> changePassword(String current, String newPassword) async {
    await AuthRepository.instance.changeOwnPassword(
      user: user,
      currentPassword: current,
      newPassword: newPassword,
    );
    final rt = _rest.refreshToken;
    if (rt != null) await _store.write(rt);
  }

  // ── Logout ───────────────────────────────────────────────────────────
  Future<void> logout() async {
    await _store.clear();
    _rest.signOut();
    // PatientsController permanent — لازم يتمسح عشان مستخدم تانى ما يشوفش بياناته
    Get.delete<PatientsController>(force: true);
    currentUser.value = null;
    Get.offAllNamed('/login');
  }

  // ── Toggle Password ──────────────────────────────────────────────────
  void togglePassword() => showPassword.value = !showPassword.value;

  // ── Navigate ─────────────────────────────────────────────────────────
  void _navigateHome() => Get.offAllNamed('/home');

  // ── Validators ──────────────────────────────────────────────────────
  String? validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'أدخل اسم المستخدم';
    return null;
  }

  String? validateCode(String? v) {
    if (v == null || v.trim().isEmpty) return 'أدخل الرقم التعريفي';
    if (v.trim().length != 4) return 'الرقم التعريفي 4 أرقام فقط';
    if (!RegExp(r'^\d{4}$').hasMatch(v.trim())) return 'أرقام فقط';
    return null;
  }

  String? validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'أدخل كلمة المرور';
    return null;
  }

  /// سياسة كلمة المرور عند الإنشاء/التغيير: 8 حروف على الأقل وفيها حرف ورقم.
  static String? validateNewPassword(String? v) {
    if (v == null || v.isEmpty) return 'أدخل كلمة المرور';
    if (v.length < 8) return 'كلمة المرور 8 خانات على الأقل';
    if (!RegExp(r'[A-Za-z؀-ۿ]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'لازم تحتوى على حروف وأرقام';
    }
    return null;
  }
}
