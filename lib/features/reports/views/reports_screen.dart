import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/intervention_excel_builder.dart';
import '../../../core/services/local_db_service.dart';
import '../../../data/models/intervention_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/firebase_rest_service.dart';
import '../../../data/repositories/intervention_repository.dart';
import '../../../data/repositories/patient_repository.dart';
import '../../auth/controllers/auth_controller.dart';

// القالب = نسخة نضيفة من ملف الإكسل المرجعي (Form Responses + Drop Downs)
const _kTemplateAsset = 'assets/templates/interventions_template.xlsx';
const _kXlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

bool get _isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

// ─────────────────────────────────────────────────────────────────────────────
//  CONTROLLER
// ─────────────────────────────────────────────────────────────────────────────
class ReportsController extends GetxController {
  final fromDate   = Rx<DateTime>(DateTime.now().subtract(const Duration(days: 30)));
  final toDate     = Rx<DateTime>(DateTime.now());
  final isLoading  = false.obs;
  final isBusy     = false.obs;   // بيبني الملف / بيحفظ / بيشارك
  final busyAction = ''.obs;      // 'save' | 'share'
  final interventions = <InterventionModel>[].obs;

  // إحصائيات
  int get total          => interventions.length;
  int get accepted       => interventions.where((i) => i.doctorResponse == 'accepted').length;
  int get rejected       => interventions.where((i) => i.doctorResponse == 'rejected').length;
  int get pending        => interventions.where((i) => i.doctorResponse == 'pending').length;
  int get partial        => interventions.where((i) => i.doctorResponse == 'partial').length;
  int get considered     => interventions.where((i) => i.doctorResponse == 'considered').length;
  int get medErrors      => interventions.where((i) => i.isMedError).length;
  int get followedUp     => interventions.where((i) => (i.followUp ?? '').isNotEmpty).length;
  double get acceptRate  => total == 0 ? 0 : (accepted / total * 100);

  Map<String, int> get byCategory {
    final map = <String, int>{};
    for (final iv in interventions) {
      map[iv.categoryAr] = (map[iv.categoryAr] ?? 0) + 1;
    }
    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return sorted;
  }

  Map<String, int> get byType {
    final map = <String, int>{};
    for (final iv in interventions) {
      final key = '${iv.typeCode} — ${iv.typeNameAr}';
      map[key] = (map[key] ?? 0) + 1;
    }
    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
    return sorted;
  }

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    try {
      final auth = AuthController.to;
      interventions.value = await InterventionRepository.instance.fetchByHospital(
        hospitalId: auth.user.hospitalId,
        from: fromDate.value,
        to:   toDate.value.add(const Duration(hours: 23, minutes: 59)),
      );
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> pickFromDate(BuildContext ctx) async {
    final d = await _pickDate(ctx, initial: fromDate.value, last: toDate.value);
    if (d != null) { fromDate.value = d; load(); }
  }

  Future<void> pickToDate(BuildContext ctx) async {
    final d = await _pickDate(ctx, initial: toDate.value, first: fromDate.value);
    if (d != null) { toDate.value = d; load(); }
  }

  Future<DateTime?> _pickDate(BuildContext ctx,
      {required DateTime initial, DateTime? first, DateTime? last}) =>
    showDatePicker(
      context:     ctx,
      initialDate: initial,
      firstDate:   first ?? DateTime(2024),
      lastDate:    last  ?? DateTime.now(),
      locale:      const Locale('ar'),
    );

  // ── Excel (نفس شكل ملف الإكسل المرجعي) ──────────────────────────────────
  String get fileName =>
      'interventions_${_ymd(fromDate.value)}_to_${_ymd(toDate.value)}.xlsx';

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// بيجمّع بيانات الفترة المختارة ويملا القالب
  Future<List<int>> _buildReport() async {
    final auth = AuthController.to;

    // 1) القالب + القوايم اللي جواه (Drop Downs)
    final tpl = await rootBundle.load(_kTemplateAsset);
    final template = tpl.buffer.asUint8List(tpl.offsetInBytes, tpl.lengthInBytes);
    final lists = TemplateLists.fromTemplate(template);

    // 2) المرضى
    final patients = await PatientRepository.instance
        .streamPatients(hospitalId: auth.user.hospitalId)
        .first;
    final patMap = {for (final p in patients) if (p.id != null) p.id!: p};

    // 3) الاسم التجاري → الاسم العلمي (من قاعدة بيانات الأدوية)
    final brandToGeneric = await _resolveGenerics(lists);

    // 4) الصيادلة (قايمة Pharmacist Names في شيت Drop Downs)
    final pharmacists = <String>[];
    try {
      final users = await AuthRepository.instance
          .fetchUsersByHospital(auth.user.hospitalId);
      pharmacists.addAll(users.where((u) => u.isPharmacist).map((u) => u.name));
    } catch (_) {/* مش مشكلة — هنكتفي بأسماء اللي ليهم تدخلات */}

    // 4.5) أسماء الأقسام (departmentId = id في Firestore)
    final deptNames = await _resolveDepartments(
        patients.map((p) => p.departmentId).toSet());

    // 5) الصفوف (من الأقدم للأحدث)
    final sorted = [...interventions]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final mapper = ReportMapper(lists, brandToGeneric: brandToGeneric);
    final departments = <String>[];
    final rows = <ReportRow>[];
    for (final iv in sorted) {
      final pat = patMap[iv.patientId];
      final deptName = pat == null
          ? ''
          : (deptNames[pat.departmentId] ?? pat.departmentId);
      if (deptName.isNotEmpty) departments.add(deptName);
      pharmacists.add(iv.addedByUserName);
      rows.add(mapper.map(ReportInput(
        patientName:      pat?.name ?? '',
        fileNumber:       pat?.fileNumber ?? '',
        department:       deptName,
        pharmacist:       iv.addedByUserName,
        date:             iv.createdAt,
        drugName:         iv.drugName,
        altDrugName:      iv.altDrugName,
        typeCode:         iv.typeCode,
        typeNameEn:       iv.typeNameEn,
        conditionName:    iv.conditionName,
        reason:           iv.reason,
        oldValue:         iv.oldValue,
        newValue:         iv.newValue,
        comment:          iv.comment,
        extraNote:        iv.extraNote,
        reference:        iv.reference,
        followUp:         iv.followUp,
        followUpAt:       iv.followUpAt,
        doctorResponse:   iv.doctorResponse,
        isMedError:       iv.isMedError,
        errorStage:       iv.errorStage,
        errorDescription: iv.errorDescription,
        errorAction:      iv.errorAction,
        errorCause:       iv.errorCause,
        errorSeverity:    iv.errorSeverity,
      )));
    }

    return InterventionExcelBuilder.build(
      template:    template,
      rows:        rows,
      departments: departments,
      pharmacists: pharmacists,
    );
  }

  /// departmentId → اسم القسم (collection: departments، الحقل name)
  Future<Map<String, String>> _resolveDepartments(Set<String> ids) async {
    final out = <String, String>{};
    for (final id in ids) {
      if (id.trim().isEmpty) continue;
      try {
        final doc = await FirebaseRestService.instance.getDoc('departments/$id');
        if (doc == null) continue;
        final d = FirebaseRestService.docData(doc);
        final name = (d['name'] ?? d['name_en'] ?? d['title'] ?? '').toString().trim();
        if (name.isNotEmpty) out[id] = name;
      } catch (_) {/* هنسيب الـ id */}
    }
    return out;
  }

  /// أي اسم دوا مش موجود في Drug List بنسأل عنه قاعدة البيانات المحلية
  Future<Map<String, String>> _resolveGenerics(TemplateLists lists) async {
    final names = <String>{};
    for (final iv in interventions) {
      for (final n in [iv.drugName, iv.altDrugName]) {
        final t = ReportMapper.cleanDrugText(n);
        if (t.isNotEmpty && !lists.isGeneric(t)) names.add(t);
      }
    }
    final out = <String, String>{};
    for (final n in names) {
      try {
        final low = n.toLowerCase();
        final tokens = low.split(RegExp(r'\s+'));
        String? generic;
        // بنبحث بالاسم كامل ثم بأول كلمات أقل (الاسم المخزّن = brand + تركيز)
        for (var k = tokens.length > 4 ? 4 : tokens.length; k >= 1 && generic == null; k--) {
          final q = tokens.take(k).join(' ');
          if (q.length < 2) continue;
          final res = await LocalDbService.instance.searchDrugs(q);
          int bestLen = -1;
          for (final r in res) {
            final b = r.brandName.trim().toLowerCase();
            if (b.isNotEmpty && r.genericName.trim().isNotEmpty &&
                low.startsWith(b) && b.length > bestLen) {
              bestLen = b.length;
              generic = r.genericName.trim();
            }
          }
          if (generic == null && k == 1 && q.length >= 4) {
            final gs = res.map((r) => r.genericName.trim()).where((g) => g.isNotEmpty).toSet();
            if (gs.length == 1) generic = gs.first;
          }
        }
        if (generic != null) out[low] = generic;
      } catch (_) {/* قاعدة الأدوية مش جاهزة — هنسيب الاسم زي ما هو */}
    }
    return out;
  }

  // ── زر التصدير: المستخدم بيختار المكان ────────────────────────────────────
  Future<void> saveToComputer() async {
    if (isBusy.value || total == 0) return;
    isBusy.value = true;
    busyAction.value = 'save';
    try {
      final bytes = await _buildReport();
      final Object? saved = await FilePicker.saveFile(
        dialogTitle:       'اختر مكان حفظ ملف الإكسل',
        fileName:          fileName,
        type:              FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes:             Uint8List.fromList(bytes), // أندرويد/iOS بيكتب منه
      );
      if (saved == null) return; // المستخدم لغى
      // النسخ الحديثة من file_picker بتكتب الملف بنفسها وبترجّع Uri
      final path = saved is Uri
          ? (saved.scheme == 'file' ? saved.toFilePath() : saved.toString())
          : saved.toString();
      Get.snackbar(
        '✅ تم التصدير',
        'تم حفظ الملف:\n$path',
        backgroundColor: AppColors.success,
        colorText: Colors.white,
        duration: const Duration(seconds: 6),
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      _error('فشل التصدير: $e');
    } finally {
      isBusy.value = false;
      busyAction.value = '';
    }
  }

  // ── زر المشاركة ─────────────────────────────────────────────────────────────
  Future<void> shareReport() async {
    if (isBusy.value || total == 0) return;
    isBusy.value = true;
    busyAction.value = 'share';
    try {
      final bytes = await _buildReport();
      final dir   = await getTemporaryDirectory();
      final file  = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path, mimeType: _kXlsxMime, name: fileName)],
        subject: fileName,
      );
    } catch (e) {
      _error('فشلت المشاركة: $e');
    } finally {
      isBusy.value = false;
      busyAction.value = '';
    }
  }

  void _error(String msg) => Get.snackbar('خطأ', msg,
      backgroundColor: AppColors.danger,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM);
}

// ─────────────────────────────────────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(ReportsController());

    return Column(
      children: [
        _DateRangeBar(ctrl: ctrl),
        Expanded(
          child: Obx(() {
            if (ctrl.isLoading.value) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryCards(ctrl: ctrl),
                const SizedBox(height: 16),
                _CategoryBreakdown(ctrl: ctrl),
                const SizedBox(height: 16),
                _TypeBreakdown(ctrl: ctrl),
                const SizedBox(height: 80),
              ],
            );
          }),
        ),
        _ExportBar(ctrl: ctrl),
      ],
    );
  }
}

// ── Date Range Bar ────────────────────────────────────────────────────────────
class _DateRangeBar extends StatelessWidget {
  final ReportsController ctrl;
  const _DateRangeBar({required this.ctrl});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(
      children: [
        const Text('من:', style: TextStyle(fontFamily:'Cairo', fontSize:13, fontWeight:FontWeight.w600)),
        const SizedBox(width: 8),
        Obx(() => _DateBtn(
          label: _fmt(ctrl.fromDate.value),
          onTap: () => ctrl.pickFromDate(context),
        )),
        const SizedBox(width: 12),
        const Text('إلى:', style: TextStyle(fontFamily:'Cairo', fontSize:13, fontWeight:FontWeight.w600)),
        const SizedBox(width: 8),
        Obx(() => _DateBtn(
          label: _fmt(ctrl.toDate.value),
          onTap: () => ctrl.pickToDate(context),
        )),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          onPressed: ctrl.load,
          tooltip: 'تحديث',
        ),
      ],
    ),
  );

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

class _DateBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(8),
        color: AppColors.primary.withOpacity(0.06),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontFamily:'Cairo', fontSize:12, color:AppColors.primary, fontWeight:FontWeight.w600)),
        ],
      ),
    ),
  );
}

// ── Summary Cards ─────────────────────────────────────────────────────────────
class _SummaryCards extends StatelessWidget {
  final ReportsController ctrl;
  const _SummaryCards({required this.ctrl});

  @override
  Widget build(BuildContext context) => Obx(() => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisSpacing: 12, mainAxisSpacing: 12,
    childAspectRatio: 1.6,
    children: [
      _StatCard(label: 'إجمالي التدخلات', value: '${ctrl.total}',
          icon: Icons.edit_note_rounded, color: AppColors.primary),
      _StatCard(
        label: 'نسبة القبول',
        value: '${ctrl.acceptRate.toStringAsFixed(0)}%',
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.success,
      ),
      _StatCard(label: 'قبل الطبيب', value: '${ctrl.accepted}',
          icon: Icons.thumb_up_outlined, color: AppColors.success),
      _StatCard(label: 'رفض الطبيب', value: '${ctrl.rejected}',
          icon: Icons.thumb_down_outlined, color: AppColors.danger),
      _StatCard(label: 'قبول جزئي', value: '${ctrl.partial}',
          icon: Icons.rule_rounded, color: AppColors.warning),
      _StatCard(label: 'أُخذ في الاعتبار', value: '${ctrl.considered}',
          icon: Icons.visibility_outlined, color: AppColors.info),
      _StatCard(label: 'أخطاء دوائية', value: '${ctrl.medErrors}',
          icon: Icons.warning_amber_rounded, color: AppColors.danger),
      _StatCard(label: 'تمت متابعتها', value: '${ctrl.followedUp}',
          icon: Icons.fact_check_outlined, color: AppColors.primary),
    ],
  ));
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(label,
              style: const TextStyle(fontFamily:'Cairo', fontSize:12, color:AppColors.textSecond))),
        ]),
        Text(value, style: TextStyle(fontFamily:'Cairo', fontSize:26,
            fontWeight:FontWeight.w700, color:color)),
      ],
    ),
  );
}

// ── Category Breakdown ────────────────────────────────────────────────────────
class _CategoryBreakdown extends StatelessWidget {
  final ReportsController ctrl;
  const _CategoryBreakdown({required this.ctrl});

  @override
  Widget build(BuildContext context) => Obx(() {
    if (ctrl.byCategory.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'التوزيع حسب الفئة',
      child: Column(
        children: ctrl.byCategory.entries.map((e) => _BarRow(
          label: e.key,
          count: e.value,
          total: ctrl.total,
          color: AppColors.primary,
        )).toList(),
      ),
    );
  });
}

// ── Type Breakdown ────────────────────────────────────────────────────────────
class _TypeBreakdown extends StatelessWidget {
  final ReportsController ctrl;
  const _TypeBreakdown({required this.ctrl});

  @override
  Widget build(BuildContext context) => Obx(() {
    if (ctrl.byType.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'التوزيع حسب نوع التدخل',
      child: Column(
        children: ctrl.byType.entries.take(10).map((e) => _BarRow(
          label: e.key,
          count: e.value,
          total: ctrl.total,
          color: AppColors.info,
        )).toList(),
      ),
    );
  });
}

class _BarRow extends StatelessWidget {
  final String label;
  final int count, total;
  final Color color;
  const _BarRow({required this.label, required this.count, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label,
                  style: const TextStyle(fontFamily:'Cairo', fontSize:12),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('$count', style: TextStyle(fontFamily:'Cairo', fontSize:12,
                  fontWeight:FontWeight.w700, color:color)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: Colors.grey.shade100,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontFamily:'Cairo', fontSize:15,
            fontWeight:FontWeight.w700, color:AppColors.textPrimary)),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

// ── Export Bar: تصدير (مكان من اختيار المستخدم) + مشاركة ───────────────────────
class _ExportBar extends StatelessWidget {
  final ReportsController ctrl;
  const _ExportBar({required this.ctrl});

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
    child: Obx(() {
      final busy     = ctrl.isBusy.value;
      final disabled = busy || ctrl.total == 0;
      final saving   = busy && ctrl.busyAction.value == 'save';
      final sharing  = busy && ctrl.busyAction.value == 'share';
      const spinner  = SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2));
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: disabled ? null : ctrl.saveToComputer,
                icon: saving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.download_rounded),
                label: Text(
                  saving
                      ? 'جاري التصدير...'
                      : '${_isDesktop ? 'تصدير على الكمبيوتر' : 'حفظ الملف'}  (${ctrl.total})',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: disabled ? null : ctrl.shareReport,
                icon: sharing ? spinner : const Icon(Icons.share_rounded),
                label: Text(
                  sharing ? 'جاري التجهيز...' : 'مشاركة',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),
        ],
      );
    }),
  );
}
