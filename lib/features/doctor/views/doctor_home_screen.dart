import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/intervention_model.dart';
import '../../../data/models/patient_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/firebase_rest_service.dart';
import '../../../data/repositories/intervention_repository.dart';
import '../../../data/repositories/org_repository.dart';
import '../../../data/repositories/patient_repository.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/views/change_password_dialog.dart';
import '../../patients/views/intervention_extras.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CONTROLLER
//  الصفحة بتجيب البيانات مرة عند الفتح وبتتحدث بالسحب/زرار التحديث (من غير polling).
// ─────────────────────────────────────────────────────────────────────────────
class DoctorController extends GetxController {
  final items     = <InterventionModel>[].obs;
  final patients  = <String, PatientModel>{}.obs;
  final isLoading = true.obs;
  final error     = ''.obs;
  final deptName  = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final u = AuthController.to.user;
    final dept = u.departmentId;
    if (u.isAdmin) return _loadAll(u);
    if (dept == null) {
      isLoading.value = false;
      error.value = 'لم يتم تعيين قسم لك. تواصل مع المدير.';
      return;
    }
    isLoading.value = true;
    error.value = '';
    try {
      final ivF   = InterventionRepository.instance
          .fetchForDoctor(hospitalId: u.hospitalId, departmentId: dept);
      final ptF   = PatientRepository.instance
          .fetchByDepartment(hospitalId: u.hospitalId, departmentId: dept);
      final dptF  = OrgRepository.instance.departments(u.hospitalId);
      final iv    = await ivF;
      final pt    = await ptF;
      final depts = await dptF;
      items.value    = iv;
      patients.value = {for (final p in pt) p.id!: p};
      deptName.value = depts.where((d) => d.id == dept).firstOrNull?.name ?? '';
    } on ApiException catch (e) {
      error.value = e.message;
    } catch (_) {
      error.value = 'تعذّر تحميل البيانات. تأكد من الإنترنت.';
    } finally {
      isLoading.value = false;
    }
  }

  /// مدير المستشفى: كل تدخلات وكل مرضى المستشفى
  Future<void> _loadAll(UserModel u) async {
    isLoading.value = true;
    error.value = '';
    try {
      final ivF = InterventionRepository.instance.fetchAllForHospital(u.hospitalId);
      final ptF = PatientRepository.instance.fetchPatients(hospitalId: u.hospitalId);
      final iv = await ivF;
      final pt = await ptF;
      items.value    = iv;
      patients.value = {for (final p in pt) p.id!: p};
      deptName.value = '';
    } on ApiException catch (e) {
      error.value = e.message;
    } catch (_) {
      error.value = 'تعذّر تحميل البيانات. تأكد من الإنترنت.';
    } finally {
      isLoading.value = false;
    }
  }

  List<InterventionModel> get pending =>
      items.where((i) => i.isPending).toList();
  List<InterventionModel> get done =>
      items.where((i) => !i.isPending).toList();

  /// تدخل كتبه الأدمن بنفسه (بيتميّز بلون بنفسجي)
  bool isAdminOwn(InterventionModel iv) =>
      AuthController.to.user.isAdmin &&
      iv.addedByUserId == AuthController.to.user.id;

  /// المدير بقى من حقه يرد على تدخلاته هو كمان.
  /// ⚠️ لازم قواعد Firestore تسمح بده (راجع firestore.rules).
  bool canRespondTo(InterventionModel iv) => true;

  /// رد الطبيب — بيتسجل فى الداتا بيز باسمه ووقت السيرفر.
  /// بيرجّع true لو نجح.
  Future<bool> respond(InterventionModel iv, String response, {String? note}) async {
    final me = AuthController.to.user;
    try {
      await InterventionRepository.instance.respondAsDoctor(
        id: iv.id!,
        response: response,
        doctor: me,
        note: note,
      );
      final i = items.indexWhere((x) => x.id == iv.id);
      if (i >= 0) {
        items[i] = iv.copyWith(
          doctorResponse: response,
          doctorNote: note,
          doctorId: me.id,
          doctorName: me.name,
          respondedAt: DateTime.now(),
        );
      }
      return true;
    } on ApiException catch (e) {
      Get.snackbar('خطأ', e.isPermissionDenied
          ? 'مش مسموح: التدخل اتردّ عليه قبل كده أو مش من قسمك'
          : e.message);
      await load();
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class DoctorHomeScreen extends StatelessWidget {
  /// true = تاب جوه شاشة المدير (من غير قايمة الحساب/الخروج)
  final bool embedded;
  const DoctorHomeScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(DoctorController());
    final me = AuthController.to.user;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Obx(() => Text(c.deptName.value.isEmpty
              ? (embedded ? 'مراجعة التدخلات' : 'تدخلات الصيادلة')
              : 'تدخلات الصيادلة — ${c.deptName.value}')),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'تحديث',
                onPressed: c.load),
            if (!embedded)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'pass') showChangePasswordDialog();
                if (v == 'logout') AuthController.to.logout();
              },
              itemBuilder: (_) => [
                PopupMenuItem(enabled: false, child: Text('د. ${me.name}')),
                const PopupMenuItem(value: 'pass', child: Text('تغيير كلمة المرور')),
                const PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج')),
              ],
            ),
          ],
          bottom: TabBar(
            labelStyle: const TextStyle(
                fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 13),
            tabs: [
              Tab(child: Obx(() => Text('بانتظار ردك (${c.pending.length})'))),
              Tab(child: Obx(() => Text('تم الرد (${c.done.length})'))),
            ],
          ),
        ),
        body: Obx(() {
          if (c.isLoading.value && c.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (c.error.value.isNotEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.error.value,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: 'Cairo', color: AppColors.danger)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: c.load, child: const Text('إعادة المحاولة')),
                  ],
                ),
              ),
            );
          }
          return TabBarView(children: [
            _InterventionList(c: c, list: c.pending),
            _InterventionList(c: c, list: c.done),
          ]);
        }),
      ),
    );
  }
}

class _InterventionList extends StatelessWidget {
  final DoctorController c;
  final List<InterventionModel> list;
  const _InterventionList({required this.c, required this.list});

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: c.load,
        child: list.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                Center(
                    child: Text('لا يوجد',
                        style: TextStyle(
                            fontFamily: 'Cairo', color: AppColors.textSecond))),
              ])
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (_, i) => _DoctorCard(
                  iv: list[i],
                  patient: c.patients[list[i].patientId],
                  ctrl: c,
                ),
              ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  CARD: بيانات المريض + تعليق الصيدلانى الإكلينيكى + أزرار القرار
// ─────────────────────────────────────────────────────────────────────────────
class _DoctorCard extends StatelessWidget {
  final InterventionModel iv;
  final PatientModel? patient;
  final DoctorController ctrl;
  const _DoctorCard({required this.iv, required this.patient, required this.ctrl});

  static const _t = TextStyle(fontFamily: 'Cairo', fontSize: 13);

  @override
  Widget build(BuildContext context) {
    final p = patient;
    final own = ctrl.isAdminOwn(iv);
    final accent = own ? AppColors.adminOwn : AppColors.primary;
    return Card(
      color: own ? AppColors.adminOwn.withOpacity(0.05) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: own
            ? const BorderSide(color: AppColors.adminOwn, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── المريض ───────────────────────────────────────────────
            if (p != null) ...[
              Row(children: [
                Expanded(
                  child: Text(p.name,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
                Text('ملف: ${p.fileNumber}',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.textSecond)),
              ]),
              const SizedBox(height: 4),
              Text(
                '${p.ageText}'
                '${p.weightKg != null ? "  •  ${p.weightKg!.toStringAsFixed(0)} kg" : ""}'
                '  •  دخول ${p.displayAdmission}',
                style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 12, color: AppColors.textSecond),
              ),
              if (p.primaryDiagnoses.isNotEmpty || p.finalDiagnoses.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      'التشخيص: ${[...p.primaryDiagnoses, ...p.finalDiagnoses].toSet().join("، ")}',
                      style: _t),
                ),
              if (p.symptoms.isNotEmpty || p.customSymptoms.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                      'الأعراض: ${[...p.symptoms, ...p.customSymptoms].join("، ")}',
                      style: _t),
                ),
              if (p.hasComorbidities && p.comorbidities.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('أمراض مزمنة: ${p.comorbidities.join("، ")}', style: _t),
                ),
              if (p.hasAllergies && p.allergies.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                      '⚠️ حساسية: ${p.allergies.map((a) => "${a.drugName} (${a.reactionType})").join("، ")}',
                      style: _t.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600)),
                ),
              _MedsExpansion(p: p),
            ] else
              const Text('بيانات المريض غير متاحة',
                  style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSecond)),

            const Divider(height: 22),

            // ── التدخل ────────────────────────────────────────────────
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${iv.typeCode} — ${iv.categoryAr}',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: accent,
                        fontWeight: FontWeight.w600)),
              ),
              if (own) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.adminOwn,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('تدخلك',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ],
              const Spacer(),
              Text('الصيدلانى: ${iv.addedByUserName}',
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 11, color: AppColors.textSecond)),
            ]),
            const SizedBox(height: 8),
            Text(iv.typeNameAr,
                style: const TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Text(iv.comment, style: _t),
            if (iv.extraNote != null && iv.extraNote!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('📝 ${iv.extraNote}',
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 12, color: AppColors.textSecond)),
            ],
            InterventionExtras(iv: iv),
            const SizedBox(height: 12),

            // ── القرار ────────────────────────────────────────────────
            if (iv.isPending && ctrl.canRespondTo(iv))
              Row(children: [
                _btn(context, 'قبول', 'accepted', AppColors.success),
                _btn(context, 'قبول جزئى', 'partial', AppColors.warning),
                _btn(context, 'أخذ بالاعتبار', 'considered', AppColors.info),
                _btn(context, 'رفض', 'rejected', AppColors.danger),
              ])
            else if (iv.isPending)
              const Text('⏳ في انتظار رد الطبيب (انت كاتب التدخل ده)',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 12, color: AppColors.textSecond))
            else
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(iv.responseLabel,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        color: iv.responseColor)),
                if (iv.doctorNote != null && iv.doctorNote!.isNotEmpty)
                  Text('ملاحظتك: ${iv.doctorNote}', style: _t),
                if (iv.doctorName != null)
                  Text(
                      'سُجّل باسم: ${iv.doctorName}'
                      '${iv.respondedAt != null ? "  •  ${_fmt(iv.respondedAt!)}" : ""}',
                      style: const TextStyle(
                          fontFamily: 'Cairo', fontSize: 11, color: AppColors.textSecond)),
              ]),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year} '
        '${l.hour.toString().padLeft(2, "0")}:${l.minute.toString().padLeft(2, "0")}';
  }

  Widget _btn(BuildContext ctx, String t, String r, Color color) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 4)),
            onPressed: () => _confirm(r),
            child: Text(t,
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          ),
        ),
      );

  Future<void> _confirm(String response) async {
    final note = TextEditingController();
    final label = switch (response) {
      'accepted' => 'قبول التدخل',
      'rejected' => 'رفض التدخل',
      'considered' => 'تم الأخذ في الاعتبار',
      _          => 'قبول جزئى',
    };
    final ok = await Get.dialog<bool>(AlertDialog(
      title: Text(label,
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('الرد هيتسجل باسمك ومش هينفع يتعدّل بعد كده.',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textSecond)),
        const SizedBox(height: 10),
        TextField(
          controller: note,
          maxLines: 2,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(labelText: 'ملاحظتك (اختيارى)'),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Get.back(result: false), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Get.back(result: true), child: const Text('تأكيد')),
      ],
    ));
    final text = note.text.trim();
    note.dispose();
    if (ok != true) return;
    await ctrl.respond(iv, response, note: text.isEmpty ? null : text);
  }
}

class _MedsExpansion extends StatelessWidget {
  final PatientModel p;
  const _MedsExpansion({required this.p});

  @override
  Widget build(BuildContext context) {
    if (p.prescribedMedications.isEmpty && p.chronicMedications.isEmpty) {
      return const SizedBox.shrink();
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: const Text('الأدوية',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600)),
        children: [
          ...p.prescribedMedications.map((m) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.medication_rounded, size: 18, color: AppColors.primary),
              title: Text(m.displayText, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)))),
          ...p.chronicMedications.map((m) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded, size: 18, color: AppColors.textSecond),
              title: Text('${m.displayText} (مزمن)',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)))),
        ],
      ),
    );
  }
}
