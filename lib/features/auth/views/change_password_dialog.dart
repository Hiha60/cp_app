import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../controllers/auth_controller.dart';

/// تغيير كلمة المرور للمستخدم نفسه (أى دور).
/// ملحوظة: المدير مش بيقدر يغيّر باسورد حد تانى (Firebase مش بيسمح من التطبيق).
Future<void> showChangePasswordDialog() async {
  final formKey = GlobalKey<FormState>();
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  var saving = false;
  String? error;

  await Get.dialog(
    StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('تغيير كلمة المرور',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: current,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'كلمة المرور الحالية'),
                  validator: (v) => (v == null || v.isEmpty) ? 'مطلوبة' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: next,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
                  validator: AuthController.validateNewPassword,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: confirm,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'تأكيد الجديدة'),
                  validator: (v) => v != next.text ? 'غير متطابقة' : null,
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!,
                      style: const TextStyle(
                          fontFamily: 'Cairo', color: AppColors.danger, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : Get.back, child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: saving
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    set(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await AuthController.to
                          .changePassword(current.text, next.text);
                      Get.back();
                      Get.snackbar('تم', 'تم تغيير كلمة المرور',
                          backgroundColor: AppColors.success,
                          colorText: Colors.white,
                          snackPosition: SnackPosition.BOTTOM);
                    } catch (e) {
                      set(() {
                        saving = false;
                        error = e.toString();
                      });
                    }
                  },
            child: Text(saving ? 'جاري الحفظ...' : 'حفظ'),
          ),
        ],
      ),
    ),
  );

  current.dispose();
  next.dispose();
  confirm.dispose();
}
