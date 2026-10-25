import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/org_models.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/firebase_rest_service.dart';
import '../../../data/repositories/org_repository.dart';
import '../../auth/controllers/auth_controller.dart';

/// الصيدلانى يطلب تغيير قسمه:
///  - المدير بيشوف الطلب فى تاب "طلبات القسم" (وعليه Badge).
///  - لو وافق ← التغيير يتطبق. لو رفض ← يختار هو القسم.
///  - لو محدّش رد خلال [kDeptAutoApproveHours] ساعة ← التغيير يتطبق تلقائيًا.
/// بيرجّع true لو الطلب اتبعت.
Future<bool> showChangeDepartmentDialog() async {
  final auth = AuthController.to;
  final org = OrgRepository.instance;
  final me = auth.user;

  List<DepartmentModel> depts;
  try {
    final pending = await org.myRequest(me.id);
    if (pending != null && pending.isPending) {
      Get.snackbar('تنبيه', 'عندك طلب تغيير قسم قيد المراجعة بالفعل');
      return false;
    }
    depts = (await org.departments(me.hospitalId))
        .where((d) => d.id != me.departmentId)
        .toList();
  } on ApiException catch (e) {
    Get.snackbar('خطأ', e.message);
    return false;
  }

  if (depts.isEmpty) {
    Get.snackbar('تنبيه', 'مفيش أقسام تانية متاحة');
    return false;
  }

  String? chosen;
  final ok = await Get.dialog<bool>(
    AlertDialog(
      title: const Text('تغيير القسم',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
      content: StatefulBuilder(
        builder: (_, set) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<String>(
              isExpanded: true,
              value: chosen,
              hint: const Text('القسم الجديد'),
              items: depts
                  .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                  .toList(),
              onChanged: (v) => set(() => chosen = v),
            ),
            const SizedBox(height: 10),
            Text(
              'هيتبعت إشعار للمدير. لو وافق أو معملش حاجة خلال '
              '$kDeptAutoApproveHours ساعة، القسم يتغيّر. '
              'ولو رفض هو اللى يختارلك القسم.',
              style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 12, color: AppColors.textSecond),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('إلغاء')),
        ElevatedButton(
            onPressed: () => Get.back(result: true), child: const Text('إرسال')),
      ],
    ),
  );
  if (ok != true || chosen == null) return false;

  try {
    await org.requestChange(user: me, toDeptId: chosen!);
    Get.snackbar('تم', 'اتبعت الطلب للمدير',
        backgroundColor: AppColors.success,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM);
    return true;
  } on AuthException catch (e) {
    Get.snackbar('تنبيه', e.message);
  } on ApiException catch (e) {
    Get.snackbar('خطأ', e.message);
  }
  return false;
}
