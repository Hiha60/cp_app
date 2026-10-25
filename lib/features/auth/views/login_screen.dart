import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../controllers/auth_controller.dart';
import '../../../core/constants/app_constants.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ AuthController بقى مسجّل permanent من main.dart، فبنجيبه بس هنا
    final ctrl = Get.find<AuthController>();
    final isWide = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: isWide ? _wideLayout(ctrl) : _narrowLayout(ctrl),
      ),
    );
  }

  // ── Wide (Windows Desktop) ───────────────────────────────────────────
  Widget _wideLayout(AuthController ctrl) => Row(
    children: [
      // جانب الـ branding
      Expanded(
        child: Container(
          color: AppColors.primary,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AppLogo(size: 100),
              const SizedBox(height: 24),
              const Text(
                'الصيدلة الإكلينيكية',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Clinical Pharmacy System',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.75),
                ),
              ),
            ],
          ),
        ),
      ),
      // جانب النموذج
      Container(
        width: 420,
        height: double.infinity,
        color: AppColors.surface,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: _LoginForm(ctrl: ctrl),
          ),
        ),
      ),
    ],
  );

  // ── Narrow (Android) ─────────────────────────────────────────────────
  Widget _narrowLayout(AuthController ctrl) => Column(
    children: [
      // Header
      Expanded(
        flex: 2,
        child: Container(
          width: double.infinity,
          color: AppColors.primary,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AppLogo(size: 72),
              const SizedBox(height: 16),
              const Text(
                'الصيدلة الإكلينيكية',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Clinical Pharmacy System',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.75),
                ),
              ),
            ],
          ),
        ),
      ),
      // Form
      Expanded(
        flex: 3,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: _LoginForm(ctrl: ctrl),
          ),
        ),
      ),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  LOGO WIDGET
// ─────────────────────────────────────────────────────────────────────────────
class _AppLogo extends StatelessWidget {
  final double size;
  const _AppLogo({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.15),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
    ),
    child: Icon(
      Icons.local_hospital_rounded,
      size: size * 0.55,
      color: Colors.white,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  LOGIN FORM
// ─────────────────────────────────────────────────────────────────────────────
class _LoginForm extends StatelessWidget {
  final AuthController ctrl;
  const _LoginForm({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Form(
      key: ctrl.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Title ──────────────────────────────────────────────────
          Text(
            'تسجيل الدخول',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 28),

          // ── اسم المستخدم ───────────────────────────────────────────
          TextFormField(
            controller: ctrl.nameCtrl,
            validator: ctrl.validateName,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // ── الرقم التعريفي (4 أرقام) ──────────────────────────────
          TextFormField(
            controller: ctrl.codeCtrl,
            validator: ctrl.validateCode,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'الرقم التعريفي',
              prefixIcon: Icon(Icons.tag_rounded),
              counterText: '',
              hintText: '0000',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // ── كلمة المرور ────────────────────────────────────────────
          Obx(() => TextFormField(
            controller: ctrl.passwordCtrl,
            validator: ctrl.validatePassword,
            obscureText: !ctrl.showPassword.value,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'كلمة المرور',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  ctrl.showPassword.value
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: ctrl.togglePassword,
                tooltip: ctrl.showPassword.value ? 'إخفاء' : 'إظهار',
              ),
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => ctrl.login(),
          )),
          const SizedBox(height: 12),

          // ── رسالة الخطأ ────────────────────────────────────────────
          Obx(() => AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: ctrl.errorMsg.value.isEmpty
                ? const SizedBox.shrink()
                : Container(
                    key: const ValueKey('error'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            ctrl.errorMsg.value,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          )),
          const SizedBox(height: 20),

          // ── زر الدخول ──────────────────────────────────────────────
          Obx(() => SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: ctrl.isLoading.value ? null : ctrl.login,
              child: ctrl.isLoading.value
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('تسجيل الدخول'),
            ),
          )),

          const SizedBox(height: 32),

          // ── Footer ─────────────────────────────────────────────────
          Text(
            '© الصيدلة الإكلينيكية',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}
