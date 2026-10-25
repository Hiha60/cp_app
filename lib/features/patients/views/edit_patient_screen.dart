import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/alert_engine.dart';
import '../../../core/services/local_db_service.dart';
import '../../../data/models/intervention_model.dart';
import '../../../data/models/patient_model.dart';
import '../../../data/repositories/intervention_repository.dart';
import '../../../data/repositories/patient_repository.dart';
import '../controllers/add_patient_controller.dart';
import 'add_patient_screen.dart'
    show DiagnosisSearch, DiagnosisTags, DxShortcutChips;
import 'drug_picker_widget.dart';
import 'fluid_section.dart';
import '../controllers/intervention_impact.dart';
import '../controllers/patients_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CONTROLLER — بيرث AddPatientController عشان يستخدم نفس منطق البحث عن
//  الأدوية/التشخيصات/الأعراض/الحساسية، ويعبّي الحالة من بيانات مريض موجود.
// ─────────────────────────────────────────────────────────────────────────────
// لون نص كل الـ chips في شاشة التعديل: أسود (وضوح)
const _chipText =
    TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.black);

class PatientEditController extends AddPatientController {
  final PatientModel original;
  final List<InterventionModel> knownInterventions;
  final List<ClinicalAlert> alerts;
  PatientEditController(this.original, this.knownInterventions, this.alerts);

  bool _movedPrimary = false; // مريض قديم تشخيصاته كانت "مبدئي" ونقلناها لـ "نهائي"

  @override
  void onInit() {
    super.onInit();
    _fill();
  }

  Future<void> _fill() async {
    final p = original;
    nameCtrl.text = p.name;
    ageCtrl.text = '${p.age}';
    monthsCtrl.text = p.ageMonths == 0 ? '' : '${p.ageMonths}';
    ageValue.value = p.age;
    monthsValue.value = p.ageMonths;
    weightManual.value = p.weightKg != null; // الوزن المحفوظ مايتغيّرش تلقائي
    weightCtrl.text = p.weightKg == null
        ? ''
        : (p.weightKg! % 1 == 0
            ? p.weightKg!.toStringAsFixed(0)
            : p.weightKg!.toString());
    fileNumCtrl.text = p.fileNumber;
    selectedDate.value = p.admissionDate;
    selectedDeptId.value = p.departmentId;
    sex.value = p.sex;
    isPregnant.value = p.isPregnant;
    if (p.weightKg == null) syncDefaultWeight(); // طفل بلا وزن → تقديري

    selectedSymptoms.assignAll(p.symptoms);
    customSymptoms.assignAll(p.customSymptoms);
    selectedComorbidities.assignAll(p.comorbidities);
    chronicMeds.assignAll(p.chronicMedications);
    prescribedMeds.assignAll(p.prescribedMedications);
    fluidOrders.assignAll(p.fluids);
    tookFluids.value = p.fluids.isNotEmpty;
    allergies.assignAll(p.allergies);
    selectedHerbs.assignAll(p.herbs.map((h) => h.name));

    var names = List<String>.from(p.finalDiagnoses);
    var ids = List<int>.from(p.finalDiagnosisIds);
    if (names.isEmpty && p.primaryDiagnoses.isNotEmpty) {
      names = List<String>.from(p.primaryDiagnoses);
      ids = List<int>.from(p.primaryDiagnosisIds);
      _movedPrimary = true;
    }
    finalDiagnoses.assignAll(names);
    if (ids.length == names.length) {
      finalDiagnosisIds.assignAll(ids);
    } else {
      // ids ناقصة (مريض قديم) — نحلّها بالاسم عشان الحذف يشتغل صح
      final fixed = <int>[];
      for (final n in names) {
        fixed.add(await _idFor(n));
      }
      finalDiagnosisIds.assignAll(fixed);
    }
  }

  Future<int> _idFor(String name) async {
    final rows = await LocalDbService.instance.searchDiagnoses(name);
    for (final r in rows) {
      if ((r['name'] as String).toLowerCase() == name.toLowerCase()) {
        return r['id'] as int;
      }
    }
    return -1;
  }

  // ── تعديل تكرار دواء موجود ───────────────────────────────────────────
  void setFrequency(
      {required bool chronic, required int index, required String freq}) {
    final list = chronic ? chronicMeds : prescribedMeds;
    final m = list[index];
    list[index] = MedicationModel(
      brandName: m.brandName,
      genericName: m.genericName,
      rxcui: m.rxcui,
      strength: m.strength,
      form: m.form,
      frequency: freq,
      normalizedGenerics: m.normalizedGenerics,
      isChronic: m.isChronic,
      doseQty: m.doseQty,
    );
  }

  void setDoseQty(
      {required bool chronic, required int index, required double? qty}) {
    final list = chronic ? chronicMeds : prescribedMeds;
    final m = list[index];
    list[index] = MedicationModel(
      brandName: m.brandName,
      genericName: m.genericName,
      rxcui: m.rxcui,
      strength: m.strength,
      form: m.form,
      frequency: m.frequency,
      normalizedGenerics: m.normalizedGenerics,
      isChronic: m.isChronic,
      doseQty: qty,
    );
  }

  Future<void> changeDoseQtySafe(bool chronic, int i, double? qty) async {
    final m = (chronic ? chronicMeds : prescribedMeds)[i];
    if (m.doseQty == qty) return;
    final ok = await _confirmImpact(
        'تغيير جرعة ${m.brandName}',
        interventionsForMed(m, knownInterventions),
        alertsForMed(m, alerts));
    if (ok) setDoseQty(chronic: chronic, index: i, qty: qty);
  }

  // ── تنبيه فوري قبل أي تغيير بيخص تدخلات/تنبيهات موجودة ─────────────────
  Future<bool> _confirmImpact(String what, List<InterventionModel> ivs,
      List<ClinicalAlert> als) async {
    if (ivs.isEmpty && als.isEmpty) return true;
    final r = await Get.dialog<bool>(_RemoveWarnDialog(what, ivs, als),
        barrierDismissible: false);
    return r == true;
  }

  Future<void> removeMedSafe(bool chronic, int i) async {
    final m = (chronic ? chronicMeds : prescribedMeds)[i];
    final ok = await _confirmImpact(
        'حذف الدواء ${m.brandName}',
        interventionsForMed(m, knownInterventions),
        alertsForMed(m, alerts));
    if (!ok) return;
    if (chronic) {
      removeChronicMed(i);
    } else {
      removePrescribedMed(i);
    }
  }

  Future<void> changeFrequencySafe(bool chronic, int i, String freq) async {
    final m = (chronic ? chronicMeds : prescribedMeds)[i];
    if (m.frequency == freq) return;
    final ok = await _confirmImpact(
        'تغيير تكرار ${m.brandName} من ${m.frequency} إلى $freq',
        interventionsForMed(m, knownInterventions),
        alertsForMed(m, alerts));
    if (ok) setFrequency(chronic: chronic, index: i, freq: freq);
  }

  Future<void> removeAllergySafe(int i) async {
    final a = allergies[i];
    final ok = await _confirmImpact('حذف حساسية ${a.drugName}',
        interventionsForAllergy(knownInterventions), alertsForAllergy(alerts));
    if (ok) removeAllergy(i);
  }

  Future<bool> _confirmCondition(String name) => _confirmImpact(
      'حذف "$name"',
      interventionsForCondition(name, knownInterventions),
      alertsForCondition(alerts));

  Future<void> removeDiagnosisSafe(String name) async {
    if (await _confirmCondition(name)) removeFinalDiagnosis(name);
  }

  Future<void> uncheckSymptomSafe(String name) async {
    if (await _confirmCondition(name)) toggleSymptom(name, false);
  }

  Future<void> uncheckComorbiditySafe(String name) async {
    if (await _confirmCondition(name)) selectedComorbidities.remove(name);
  }

  // الحذف من الاختصارات/الـ tags يعدّي على تأكيد التأثير
  @override
  Future<void> removeComorbidity(String name) => uncheckComorbiditySafe(name);

  @override
  Future<void> removeDiagnosis(String name) => removeDiagnosisSafe(name);

  Future<void> toggleHerbSafe(String name) async {
    if (selectedHerbs.contains(name)) {
      final ok = await _confirmImpact(
          'حذف العشب $name',
          interventionsForHerb(name, knownInterventions),
          alertsForHerb(name, alerts));
      if (!ok) return;
    }
    toggleHerb(name);
  }

  Future<void> pickAdmissionDate(BuildContext context) async {
    final now = DateTime.now();
    final cur = selectedDate.value ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: cur.isAfter(now) ? now : cur,
      firstDate: DateTime(2020),
      lastDate: now,
      locale: const Locale('ar'),
    );
    if (d != null) selectedDate.value = d;
  }

  String _latinDigits(String s) {
    final b = StringBuffer();
    for (final u in s.runes) {
      if (u >= 0x0660 && u <= 0x0669) {
        b.writeCharCode(0x30 + (u - 0x0660));
      } else if (u >= 0x06F0 && u <= 0x06F9) {
        b.writeCharCode(0x30 + (u - 0x06F0));
      } else {
        b.writeCharCode(u);
      }
    }
    return b.toString();
  }

  void _warn(String msg) => Get.snackbar('تنبيه', msg,
      backgroundColor: AppColors.warning,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM);

  PatientModel _buildEdited(int age, int months) {
    final o = original;
    return PatientModel(
      id: o.id,
      hospitalId: o.hospitalId,
      departmentId: o.departmentId,
      addedByUserId: o.addedByUserId,
      addedByUserName: o.addedByUserName,
      name: nameCtrl.text.trim(),
      age: age,
      ageMonths: months,
      weightKg: double.tryParse(_latinDigits(weightCtrl.text.trim())),
      fileNumber: fileNumCtrl.text.trim(),
      sex: sex.value,
      isPregnant: sex.value == 'F' && isPregnant.value,
      labResults: o.labResults,
      admissionDate: selectedDate.value ?? o.admissionDate,
      status: o.status,
      primaryDiagnoses: _movedPrimary ? const [] : o.primaryDiagnoses,
      primaryDiagnosisIds: _movedPrimary ? const [] : o.primaryDiagnosisIds,
      finalDiagnoses: finalDiagnoses.toList(),
      finalDiagnosisIds: finalDiagnosisIds.toList(),
      symptoms: selectedSymptoms.toList(),
      customSymptoms: customSymptoms.toList(),
      hasComorbidities: selectedComorbidities.isNotEmpty,
      comorbidities: selectedComorbidities.toList(),
      hasChronicMedications: chronicMeds.isNotEmpty,
      chronicMedications: chronicMeds.toList(),
      hasAllergies: allergies.isNotEmpty,
      allergies: allergies.toList(),
      hasHerbs: selectedHerbs.isNotEmpty,
      herbs: selectedHerbs.map((n) => HerbModel(name: n)).toList(),
      prescribedMedications: prescribedMeds.toList(),
      fluids: tookFluids.value ? fluidOrders.toList() : const [],
      createdAt: o.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  static const _editableKeys = [
    'name', 'age', 'age_months', 'weight_kg', 'file_number', 'admission_date',
    'sex', 'is_pregnant',
    'primary_diagnoses', 'primary_diagnosis_ids',
    'final_diagnoses', 'final_diagnosis_ids',
    'symptoms', 'custom_symptoms',
    'has_comorbidities', 'comorbidities',
    'has_chronic_medications', 'chronic_medications',
    'has_allergies', 'allergies',
    'has_herbs', 'herbs',
    'prescribed_medications', 'fluids', 'updated_at',
  ];

  /// يحفظ التعديلات. لو التعديل بيخص تدخلات مسجّلة بيسأل قبل أي حذف.
  Future<void> saveEdit() async {
    if (isSaving.value) return;
    final ageStr = _latinDigits(ageCtrl.text.trim());
    final monthsStr = _latinDigits(monthsCtrl.text.trim());
    final months = monthsStr.isEmpty ? 0 : int.tryParse(monthsStr);
    final age = (ageStr.isEmpty && monthsStr.isEmpty)
        ? null
        : (ageStr.isEmpty ? 0 : int.tryParse(ageStr));
    if (nameCtrl.text.trim().isEmpty) {
      _warn('أدخل اسم المريض');
      return;
    }
    if (age == null || age < 0 || age > 120) {
      _warn('السن غير صحيح');
      return;
    }
    if (months == null || months < 0 || months > 11) {
      _warn('الشهور من 0 إلى 11');
      return;
    }
    if (fileNumCtrl.text.trim().isEmpty) {
      _warn('أدخل رقم الملف');
      return;
    }

    isSaving.value = true;
    try {
      final o = original;
      final edited = _buildEdited(age, months);

      // رقم الملف اتغيّر → نتأكد إنه مش لمريض تاني
      if (edited.fileNumber != o.fileNumber) {
        final dup = await PatientRepository.instance.findDuplicate(
          hospitalId: o.hospitalId,
          departmentId: o.departmentId,
          fileNumber: edited.fileNumber,
          admissionDate: edited.admissionDate,
        );
        if (dup != null && dup.id != o.id) {
          _warn('رقم الملف مسجّل لمريض آخر (${dup.name})');
          return;
        }
      }

      // أحدث تدخلات المريض من السيرفر (لو فشل نستخدم اللي معانا)
      var ivs = knownInterventions;
      try {
        ivs = await InterventionRepository.instance.fetchByPatient(o.id!, hospitalId: o.hospitalId);
      } catch (_) {}

      final affected =
          affectedInterventions(before: o, after: edited, interventions: ivs);
      final affectedAl =
          affectedAlerts(before: o, after: edited, alerts: alerts);

      var deleteThem = false;
      if (affected.isNotEmpty || affectedAl.isNotEmpty) {
        final choice = await Get.dialog<String>(
          _ImpactDialog(affected, affectedAl),
          barrierDismissible: false,
        );
        if (choice == null || choice == 'cancel') return;
        deleteThem = choice == 'delete';
      }

      final full = edited.toRestMap();
      await PatientRepository.instance
          .updatePatient(o.id!, {for (final k in _editableKeys) k: full[k]});

      // الحذف بعد نجاح حفظ المريض (لو الحفظ فشل ما نمسحش حاجة)
      var failed = 0;
      if (deleteThem) {
        for (final a in affected) {
          try {
            await InterventionRepository.instance
                .deleteIntervention(a.iv.id!);
          } catch (_) {
            failed++;
          }
        }
      }

      if (Get.isRegistered<PatientsController>()) {
        PatientsController.to.markDirty();
      }
      Get.back(result: true);
      Get.snackbar(
        '✅ تم',
        failed == 0
            ? 'تم حفظ التعديلات${deleteThem ? ' وحذف ${affected.length} تدخل' : ''}'
            : 'تم حفظ التعديلات، لكن تعذّر حذف $failed تدخل (مسموح بحذف تدخلاتك أنت فقط وقبل رد الطبيب)',
        backgroundColor: failed == 0 ? AppColors.success : AppColors.warning,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar('خطأ', 'فشل حفظ التعديلات: $e',
          backgroundColor: AppColors.danger,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isSaving.value = false;
    }
  }
}

// ── عناصر عرض مشتركة للـ Dialogs ───────────────────────────────────────────
Widget _ivTile(InterventionModel iv, [String? reason]) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🩺 تدخل ${iv.typeCode} — ${iv.typeNameAr}',
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
          const SizedBox(height: 2),
          Text(iv.comment,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          if (reason != null) ...[
            const SizedBox(height: 2),
            Text('السبب: $reason',
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: AppColors.textSecond)),
          ],
        ],
      ),
    );

Widget _alertTile(ClinicalAlert a, [String? reason]) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.info.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🔔 تنبيه ${a.severityLabel} (${a.typeCode})',
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
          const SizedBox(height: 2),
          Text(a.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          if (reason != null) ...[
            const SizedBox(height: 2),
            Text('السبب: $reason',
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: AppColors.textSecond)),
          ],
        ],
      ),
    );

// ── Dialog فوري: قبل حذف/تغيير عنصر مرتبط بتدخلات أو تنبيهات ─────────────────
class _RemoveWarnDialog extends StatelessWidget {
  final String what;
  final List<InterventionModel> ivs;
  final List<ClinicalAlert> als;
  const _RemoveWarnDialog(this.what, this.ivs, this.als);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text('تنبيه قبل التعديل',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ),
        ]),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$what — مرتبط بما يلي:',
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ...ivs.map((iv) => _ivTile(iv)),
                    ...als.map((a) => _alertTile(a)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              if (ivs.isNotEmpty)
                const Text(
                    '• التدخلات لن تُحذف إلا بعد تأكيدك عند الحفظ.',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
              if (als.isNotEmpty)
                const Text(
                    '• التنبيهات تُحسب تلقائياً من البيانات، وستتغيّر أو تختفي بعد الحفظ.',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Get.back(result: true),
            child: const Text('متابعة التعديل'),
          ),
        ],
      );
}

// ── Dialog الحفظ: التعديل بيخص تدخلات و/أو تنبيهات ───────────────────────────
class _ImpactDialog extends StatelessWidget {
  final List<AffectedIntervention> items;
  final List<AffectedAlert> alertItems;
  const _ImpactDialog(this.items, this.alertItems);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text('التعديلات تخص تدخلات/تنبيهات',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
          ),
        ]),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (items.isNotEmpty)
                Text('${items.length} تدخل مسجّل متأثر — اختر ماذا تفعل بها:',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
              if (alertItems.isNotEmpty)
                Text('${alertItems.length} تنبيه سيتغيّر أو يختفي بعد الحفظ.',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ...items.map((a) => _ivTile(a.iv, a.reason)),
                    ...alertItems.map((a) => _alertTile(a.alert, a.reason)),
                  ],
                ),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text(
                  'حذف التدخل نهائي ويؤثر على التقارير ولا يمكن التراجع عنه.',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: AppColors.danger),
                ),
              ],
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actionsOverflowButtonSpacing: 6,
        actions: [
          TextButton(
            onPressed: () => Get.back(result: 'cancel'),
            child: const Text('رجوع للتعديل'),
          ),
          OutlinedButton(
            onPressed: () => Get.back(result: 'keep'),
            child: Text(items.isEmpty ? 'متابعة الحفظ' : 'حفظ وإبقاء التدخلات'),
          ),
          if (items.isNotEmpty)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Get.back(result: 'delete'),
              child: Text('حفظ وحذف ${items.length} تدخل'),
            ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class EditPatientScreen extends StatefulWidget {
  final PatientModel patient;
  final List<InterventionModel> interventions;
  final List<ClinicalAlert> alerts;
  const EditPatientScreen(
      {super.key,
      required this.patient,
      this.interventions = const [],
      this.alerts = const []});

  @override
  State<EditPatientScreen> createState() => _EditPatientScreenState();
}

class _EditPatientScreenState extends State<EditPatientScreen> {
  late final String _tag = 'edit_${widget.patient.id}';
  late final PatientEditController ctrl;

  @override
  void initState() {
    super.initState();
    // دايماً controller جديد (بيانات طازة من المريض المفتوح)
    if (Get.isRegistered<PatientEditController>(tag: _tag)) {
      Get.delete<PatientEditController>(tag: _tag, force: true);
    }
    ctrl = Get.put(
        PatientEditController(
            widget.patient, widget.interventions, widget.alerts),
        tag: _tag);
  }

  @override
  void dispose() {
    if (Get.isRegistered<PatientEditController>(tag: _tag)) {
      Get.delete<PatientEditController>(tag: _tag, force: true);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
        // كل الـ chips بنص أسود وعلامات سوداء (وضوح)
        data: Theme.of(context).copyWith(
          chipTheme: Theme.of(context).chipTheme.copyWith(
                labelStyle: _chipText,
                secondaryLabelStyle: _chipText,
                checkmarkColor: Colors.black,
                deleteIconColor: Colors.black,
              ),
        ),
        child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('تعديل بيانات المريض'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded),
              tooltip: 'رجوع بدون حفظ',
              onPressed: () => Get.back(),
            ),
          ),
          body: Column(
            children: [
              Material(
                color: Colors.white,
                child: TabBar(
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecond,
                  indicatorColor: AppColors.primary,
                  labelStyle: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                  tabs: const [
                    Tab(text: 'البيانات'),
                    Tab(text: 'التشخيص والأعراض'),
                    Tab(text: 'الأدوية'),
                    Tab(text: 'الحساسية والأعشاب'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _BasicTab(ctrl: ctrl),
                    _DxTab(ctrl: ctrl),
                    _MedsEditTab(ctrl: ctrl),
                    _AllergyTab(ctrl: ctrl),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Obx(() => SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: ctrl.isSaving.value ? null : ctrl.saveEdit,
                      icon: ctrl.isSaving.value
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_rounded),
                      label: Text(
                          ctrl.isSaving.value ? 'جاري الحفظ...' : 'حفظ التعديلات'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success),
                    ),
                  )),
            ),
          ),
        ),
        ),
      );
}

// ── helpers ──────────────────────────────────────────────────────────────────
class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
      );
}

// ── Tab 1: البيانات الأساسية ────────────────────────────────────────────────
class _BasicTab extends StatelessWidget {
  final PatientEditController ctrl;
  const _BasicTab({required this.ctrl});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Title('البيانات الأساسية'),
          TextField(
            controller: ctrl.nameCtrl,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
                labelText: 'اسم المريض',
                prefixIcon: Icon(Icons.person_outline_rounded)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: ctrl.ageCtrl,
                onChanged: ctrl.onAgeChanged,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(labelText: 'السن (سنة)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: ctrl.monthsCtrl,
                onChanged: ctrl.onMonthsChanged,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(labelText: 'الشهور (0–11)'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl.weightCtrl,
            onChanged: ctrl.onWeightEdited,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(labelText: 'الوزن (kg)'),
          ),
          Obx(() => ctrl.weightEstimated.value
              ? const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                      'وزن تقديري حسب السن — عدّله لو الوزن الفعلي معروف',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: AppColors.warning)),
                )
              : ctrl.weightManual.value && ctrl.canEstimateWeight.value
                  ? Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: ctrl.useEstimatedWeight,
                        child: const Text('استخدم الوزن التقديري للسن',
                            style:
                                TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                      ),
                    )
                  : const SizedBox.shrink()),
          const SizedBox(height: 12),
          const Text('الجنس',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          const SizedBox(height: 6),
          Obx(() => SegmentedButton<String>(
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'M', label: Text('ذكر')),
                  ButtonSegment(value: 'F', label: Text('أنثى')),
                ],
                selected:
                    ctrl.sex.value == null ? <String>{} : {ctrl.sex.value!},
                onSelectionChanged: (s) {
                  ctrl.sex.value = s.isEmpty ? null : s.first;
                  if (ctrl.sex.value != 'F') ctrl.isPregnant.value = false;
                },
              )),
          Obx(() => ctrl.sex.value == 'F'
              ? SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title:
                      const Text('حامل', style: TextStyle(fontFamily: 'Cairo')),
                  value: ctrl.isPregnant.value,
                  onChanged: (v) => ctrl.isPregnant.value = v,
                )
              : const SizedBox.shrink()),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl.fileNumCtrl,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
                labelText: 'رقم الملف',
                prefixIcon: Icon(Icons.folder_outlined)),
          ),
          const SizedBox(height: 12),
          Obx(() => OutlinedButton.icon(
                onPressed: () => ctrl.pickAdmissionDate(context),
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(ctrl.selectedDate.value == null
                    ? 'تاريخ الدخول'
                    : 'تاريخ الدخول: ${ctrl.selectedDate.value!.day}/${ctrl.selectedDate.value!.month}/${ctrl.selectedDate.value!.year}'),
              )),
          const _Title('الأمراض المزمنة'),
          DxShortcutChips(ctrl: ctrl, comorbidity: true),
          const SizedBox(height: 10),
          DiagnosisSearch(
            ctrl: ctrl,
            comorbidity: true,
            onSelect: (id, name) => ctrl.addComorbidity(name),
            hint: 'ابحث عن مرض مزمن...',
          ),
          Obx(() => DiagnosisTags(
                items: ctrl.selectedComorbidities.toList(),
                onRemove: ctrl.removeComorbidity,
                color: AppColors.primary,
              )),
        ],
      );
}

// ── Tab 2: التشخيص والأعراض ─────────────────────────────────────────────────
class _DxTab extends StatefulWidget {
  final PatientEditController ctrl;
  const _DxTab({required this.ctrl});
  @override
  State<_DxTab> createState() => _DxTabState();
}

class _DxTabState extends State<_DxTab> {
  final _dx = TextEditingController();
  final _sym = TextEditingController();

  @override
  void dispose() {
    _dx.dispose();
    _sym.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Title('التشخيص النهائي'),
        DxShortcutChips(ctrl: ctrl, comorbidity: false),
        const SizedBox(height: 10),
        TextField(
          controller: _dx,
          onChanged: ctrl.searchDiagnosis,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
              hintText: 'ابحث لإضافة تشخيص...',
              prefixIcon: Icon(Icons.search_rounded)),
        ),
        Obx(() => Column(
              children: ctrl.diagSearchResults
                  .map((d) => ListTile(
                        dense: true,
                        title: Text(d['name'] as String,
                            style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 13)),
                        trailing: d['icd10'] != null
                            ? Text('${d['icd10']}',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textSecond))
                            : null,
                        onTap: () async {
                          final id = d['id'] as int;
                          final name = d['name'] as String;
                          _dx.clear();
                          ctrl.diagSearchResults.clear();
                          await ctrl.addFinalDiagnosis(id, name);
                        },
                      ))
                  .toList(),
            )),
        Obx(() => Wrap(
              spacing: 8,
              runSpacing: 6,
              children: ctrl.finalDiagnoses
                  .map((n) => Chip(
                        label: Text(n, style: _chipText),
                        deleteIcon: const Icon(Icons.close_rounded, size: 14),
                        onDeleted: () => ctrl.removeDiagnosisSafe(n),
                      ))
                  .toList(),
            )),
        const _Title('الأعراض'),
        Obx(() {
          final all = <String>{
            ...ctrl.topSymptoms,
            ...ctrl.selectedSymptoms,
          }.toList();
          return Wrap(
            spacing: 8,
            runSpacing: 6,
            children: all.map((s) {
              final sel = ctrl.selectedSymptoms
                  .any((x) => x.toLowerCase() == s.toLowerCase());
              return FilterChip(
                label: Text(s, style: _chipText),
                selected: sel,
                onSelected: (on) => on
                    ? ctrl.toggleSymptom(s, true)
                    : ctrl.uncheckSymptomSafe(s),
              );
            }).toList(),
          );
        }),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _sym,
              textDirection: TextDirection.ltr,
              onChanged: ctrl.searchSymptom,
              decoration: const InputDecoration(
                  hintText: 'أضف عرضاً (بالإنجليزية)...'),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () async {
              final ok = await ctrl.addCustomSymptom(_sym.text);
              if (ok) _sym.clear();
            },
            child: const Text('إضافة'),
          ),
        ]),
        Obx(() => ctrl.symptomHint.value.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(ctrl.symptomHint.value,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.danger)),
              )),
        Obx(() => Wrap(
              spacing: 8,
              children: ctrl.symptomSuggestions
                  .map((s) => ActionChip(
                        label: Text(s, style: _chipText),
                        onPressed: () {
                          ctrl.toggleSymptom(s, true);
                          ctrl.symptomSuggestions.clear();
                          _sym.clear();
                        },
                      ))
                  .toList(),
            )),
      ],
    );
  }
}

// ── Tab 3: الأدوية ──────────────────────────────────────────────────────────
class _MedsEditTab extends StatefulWidget {
  final PatientEditController ctrl;
  const _MedsEditTab({required this.ctrl});
  @override
  State<_MedsEditTab> createState() => _MedsEditTabState();
}

class _MedsEditTabState extends State<_MedsEditTab> {
  final _tc = TextEditingController();
  bool _chronic = false;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _pickFreq(bool chronic, int index) async {
    final ctrl = widget.ctrl;
    final f = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kFrequencies
              .map((f) => ActionChip(
                    label: Text(f, style: _chipText),
                    onPressed: () => Navigator.pop(context, f),
                  ))
              .toList(),
        ),
      ),
    );
    if (f != null) ctrl.changeFrequencySafe(chronic, index, f);
  }

  Future<void> _pickDoseQty(bool chronic, int index) async {
    final m = (chronic ? widget.ctrl.chronicMeds : widget.ctrl.prescribedMeds)[index];
    final opts = doseQtyOptionsFor(
        strength: m.strength, form: m.form, brandName: m.brandName);
    if (opts == null) return;
    // -1 = مسح القيمة
    final v = await showModalBottomSheet<double>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...opts.values.map((v) => ActionChip(
                  label: Text(opts.isMl ? '${fmtQty(v)} مل' : fmtQty(v),
                      style: _chipText),
                  onPressed: () => Navigator.pop(context, v),
                )),
            ActionChip(
              label: Text('مسح', style: _chipText),
              onPressed: () => Navigator.pop(context, -1.0),
            ),
          ],
        ),
      ),
    );
    if (v == null) return;
    widget.ctrl.changeDoseQtySafe(chronic, index, v < 0 ? null : v);
  }

  Widget _medList(RxList<MedicationModel> list, bool chronic) {
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('لا توجد أدوية',
            style: TextStyle(
                fontFamily: 'Cairo', fontSize: 12, color: AppColors.textSecond)),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < list.length; i++)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              dense: true,
              title: Text(list[i].brandName,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              subtitle: Text(
                  '${list[i].genericName} — ${list[i].strength} — ${list[i].form}'
                  '${list[i].doseQty == null ? '' : ' — جرعة: ${fmtQty(list[i].doseQty!)}'}',
                  style: const TextStyle(fontSize: 11)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (doseQtyOptionsFor(
                        strength: list[i].strength,
                        form: list[i].form,
                        brandName: list[i].brandName) !=
                    null)
                  IconButton(
                    tooltip: 'عدد الأقراص / المل في الجرعة',
                    icon: const Icon(Icons.scale_outlined, size: 18),
                    onPressed: () => _pickDoseQty(chronic, i),
                  ),
                TextButton(
                  onPressed: () => _pickFreq(chronic, i),
                  child: Text(list[i].frequency,
                      style: const TextStyle(fontSize: 12)),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded,
                      color: AppColors.danger, size: 20),
                  onPressed: () => widget.ctrl.removeMedSafe(chronic, i),
                ),
              ]),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Title('الأدوية الموصوفة'),
        Obx(() => _medList(ctrl.prescribedMeds, false)),
        const _Title('الأدوية المزمنة'),
        Obx(() => _medList(ctrl.chronicMeds, true)),
        const Divider(height: 28),
        const _Title('إضافة دواء'),
        Wrap(spacing: 8, children: [
          ChoiceChip(
            label: const Text('موصوف', style: _chipText),
            selected: !_chronic,
            onSelected: (_) => setState(() => _chronic = false),
          ),
          ChoiceChip(
            label: const Text('مزمن', style: _chipText),
            selected: _chronic,
            onSelected: (_) => setState(() => _chronic = true),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _tc,
          onChanged: ctrl.searchDrug,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            hintText: 'Augmentin, Amoxil...',
            prefixIcon: const Icon(Icons.medication_outlined),
            suffixIcon: Obx(() => ctrl.selectedDrug.value == null
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () {
                      _tc.clear();
                      ctrl.drugSearchResults.clear();
                      ctrl.resetDrugSelection();
                    },
                  )),
          ),
        ),
        Obx(() => Column(
              children: ctrl.drugSearchResults
                  .map((d) => ListTile(
                        dense: true,
                        title: Text(d.brandName,
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                        subtitle: Text(d.genericName,
                            style: const TextStyle(fontSize: 11)),
                        onTap: () {
                          _tc.text = d.brandName;
                          ctrl.selectDrug(d);
                        },
                      ))
                  .toList(),
            )),
        Obx(() => ctrl.drugStrengths.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: ctrl.drugStrengths
                      .map((l) => ChoiceChip(
                            label: Text(l, style: _chipText),
                            selected: ctrl.selectedStrengthLabel.value == l,
                            onSelected: (_) => ctrl.selectStrengthChoice(l),
                          ))
                      .toList(),
                ),
              )),
        Obx(() {
          if (ctrl.selectedStrength.value == null) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الصنف: ${ctrl.selectedStrengthLabel.value}',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.textSecond)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: kFrequencies
                      .map((f) => ChoiceChip(
                            label: Text(f, style: _chipText),
                            selected: ctrl.selectedFrequency.value == f,
                            onSelected: (_) => ctrl.selectFrequency(f),
                          ))
                      .toList(),
                ),
                DoseQtyChips(ctrl: ctrl),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),
        Obx(() => ElevatedButton.icon(
              onPressed: ctrl.canAddMed
                  ? () {
                      if (_chronic) {
                        ctrl.addChronicMed();
                      } else {
                        ctrl.addPrescribedMed();
                      }
                      _tc.clear();
                    }
                  : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(_chronic
                  ? 'إضافة للأدوية المزمنة'
                  : 'إضافة للأدوية الموصوفة'),
            )),
        FluidSection(ctrl: ctrl),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Tab 4: الحساسية والأعشاب ────────────────────────────────────────────────
class _AllergyTab extends StatefulWidget {
  final PatientEditController ctrl;
  const _AllergyTab({required this.ctrl});
  @override
  State<_AllergyTab> createState() => _AllergyTabState();
}

class _AllergyTabState extends State<_AllergyTab> {
  final _tc = TextEditingController();
  DrugSearchResult? _picked;
  String _reaction = kAllergyTypes.first;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _add() {
    final d = _picked;
    if (d == null) return;
    if (d.genericTokens.isEmpty) {
      Get.snackbar('تنبيه', 'مفيش مادة فعالة مسجّلة لهذا الدواء',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    widget.ctrl.addAllergy(
      label: d.genericName.isNotEmpty ? d.genericName : d.brandName,
      reactionType: _reaction,
      scopeTokens: d.genericTokens,
    );
    setState(() => _picked = null);
    _tc.clear();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Title('الحساسية'),
        Obx(() => ctrl.allergies.isEmpty
            ? const Text('لا توجد حساسية مسجّلة',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: AppColors.textSecond))
            : Column(
                children: [
                  for (var i = 0; i < ctrl.allergies.length; i++)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        dense: true,
                        leading: const Icon(Icons.warning_amber_rounded,
                            color: AppColors.warning, size: 20),
                        title: Text(ctrl.allergies[i].drugName,
                            style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 13)),
                        subtitle: Text(
                            '${ctrl.allergies[i].reactionType}${ctrl.allergies[i].className != null ? ' — عيلة ${ctrl.allergies[i].className}' : ''}',
                            style: const TextStyle(fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded,
                              color: AppColors.danger, size: 20),
                          onPressed: () => ctrl.removeAllergySafe(i),
                        ),
                      ),
                    ),
                ],
              )),
        const SizedBox(height: 12),
        TextField(
          controller: _tc,
          onChanged: (q) {
            setState(() => _picked = null);
            ctrl.searchAllergyDrug(q);
          },
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
              hintText: 'ابحث عن دواء/مادة الحساسية...',
              prefixIcon: Icon(Icons.search_rounded)),
        ),
        Obx(() => Column(
              children: ctrl.allergyDrugResults
                  .map((d) => ListTile(
                        dense: true,
                        title: Text(d.brandName,
                            style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 13)),
                        subtitle: Text(d.genericName,
                            style: const TextStyle(fontSize: 11)),
                        onTap: () {
                          setState(() => _picked = d);
                          _tc.text = d.genericName.isNotEmpty
                              ? d.genericName
                              : d.brandName;
                          ctrl.allergyDrugResults.clear();
                        },
                      ))
                  .toList(),
            )),
        if (_picked != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _reaction,
                decoration: const InputDecoration(labelText: 'نوع التفاعل'),
                items: kAllergyTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _reaction = v ?? _reaction),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('إضافة'),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('تُسجَّل الحساسية للمادة الفعالة لهذا الدواء فقط.',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: AppColors.textSecond)),
        ],
        const _Title('الأعشاب'),
        Obx(() => Wrap(
              spacing: 8,
              runSpacing: 6,
              children: ctrl.allHerbs
                  .map((h) => FilterChip(
                        label: Text(h, style: _chipText),
                        selected: ctrl.selectedHerbs.contains(h),
                        onSelected: (_) => ctrl.toggleHerbSafe(h),
                      ))
                  .toList(),
            )),
        const SizedBox(height: 24),
      ],
    );
  }
}
