import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/intervention_fields.dart';
import '../../../core/constants/error_lists.dart';
import '../../../core/constants/iv_fluids.dart';
import '../../../core/services/intervention_suggester.dart';
import '../../../data/repositories/org_repository.dart';
import 'intervention_extras.dart';
import '../../../core/services/alert_engine.dart';
import '../../../core/services/local_db_service.dart';
import '../../../data/models/patient_model.dart';
import '../../../data/models/intervention_model.dart';
import '../../../data/repositories/patient_repository.dart';
import '../../../data/repositories/intervention_repository.dart';
import '../../auth/controllers/auth_controller.dart';
import '../controllers/patients_controller.dart';
import 'edit_patient_screen.dart';
import 'patient_labs_tab.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CONTROLLER
// ─────────────────────────────────────────────────────────────────────────────
class PatientFileController extends GetxController {
  final String patientId;
  PatientFileController(this.patientId);

  final patient = Rx<PatientModel?>(null);
  final interventions = <InterventionModel>[].obs;
  final alerts = <ClinicalAlert>[].obs;
  final isAnalyzing = false.obs;
  final tabIndex = 0.obs;

  // ── التحاليل (DB v1.0.6+) ──
  final recommendedLabs = <RecommendedLab>[].obs;
  final labRanges = <String, LabRange?>{}.obs;
  final labTests = <String, LabTest>{}.obs;
  final isLoading = true.obs;
  final loadError = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// تحميل مرة واحدة عند فتح الملف (أو بزر التحديث) — مفيش polling.
  /// فتح الملف تاني = controller جديد = تحميل جديد.
  Future<void> load() async {
    isLoading.value = true;
    loadError.value = '';
    try {
      final results = await Future.wait([
        PatientRepository.instance.fetchPatient(patientId),
        InterventionRepository.instance.fetchByPatient(patientId,
            hospitalId: AuthController.to.user.hospitalId),
      ]);
      final p = results[0] as PatientModel?;
      interventions.value = results[1] as List<InterventionModel>;
      patient.value = p;
      if (p == null) {
        loadError.value = 'الملف غير موجود';
      } else {
        refreshAlerts(refetchPatterns: true); // مرة لكل تحميل
      }
    } catch (e) {
      debugPrint('PatientFile load error: $e');
      if (patient.value == null) {
        loadError.value = '$e';
      } else {
        Get.snackbar('تعذّر التحديث', '$e',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: AppColors.danger,
            colorText: Colors.white);
      }
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> reloadInterventions() async {
    try {
      interventions.value =
          await InterventionRepository.instance.fetchByPatient(patientId,
              hospitalId: AuthController.to.user.hospitalId);
    } catch (e) {
      debugPrint('reloadInterventions error: $e');
    }
  }

  // ── تحليل التنبيهات: تشغيل واحد في كل مرة. أي طلب جديد أثناء التشغيل
  // بيتحط في الطابور ويتنفّذ على آخر نسخة من patient.value (مفيش نتيجة قديمة تكسب)
  bool _alertsRunning = false;
  bool _alertsQueued = false;
  bool _refetchPatterns = false;
  bool _patternsLoaded = false;
  List<Map<String, dynamic>> _patterns = const [];

  /// نقطة الدخول الوحيدة لإعادة حساب التنبيهات — نادِها بعد أي تغيير
  Future<void> refreshAlerts({bool refetchPatterns = false}) async {
    if (refetchPatterns) _refetchPatterns = true;
    if (_alertsRunning) {
      _alertsQueued = true;
      return;
    }
    _alertsRunning = true;
    isAnalyzing.value = true;
    try {
      do {
        _alertsQueued = false;
        final p = patient.value;
        if (p == null) break;
        await _computeAlerts(p);
      } while (_alertsQueued);
    } finally {
      _alertsRunning = false;
      isAnalyzing.value = false;
    }
  }

  Future<void> _computeAlerts(PatientModel p) async {
    try {
      final allMeds = [...p.prescribedMedications, ...p.chronicMedications];
      final snapshots = allMeds.asMap().entries.map((e) {
        final m = e.value;
        // ✅ نبني genericTokens من normalizedGenerics المخزّن في MedicationModel
        // normalized_generics مفصولة بـ "|" — مثال: "warfarin" أو "amoxicillin|clavulanate"
        final tokens = m.normalizedGenerics
            .split('|')
            .map((e) => e.trim().toLowerCase())
            .where((e) => e.isNotEmpty)
            .toList();
        return MedSnapshot(
          drugId: e.key + 1, // id فريد لكل دواء عشان منع تكرار التنبيه الرقمي يشتغل صح
          brandName: m.brandName,
          genericName: m.genericName,
          rxcui: m.rxcui,
          genericTokens: tokens,
          strengthMg: parseStrengthMg(m.strength),
          strengthRaw: m.strength,
          form: m.form,
          frequency: m.frequency,
          freqPerDay: parseFreqPerDay(m.frequency),
          isChronic: m.isChronic,
          doseQty: m.doseQty,
        );
      }).toList();

      // الأمبولات/الفيالات المضافة على المحاليل: بتدخل فحص الحساسية والتداخلات
      // (isChronic=true عشان ما يتفحصش لها "مؤشر علاجي" ولا تتحسب جرعة يومية).
      // + بنبني MedSnapshot للمحلول نفسه (شكل INF + محتواه) عشان يدخل التداخلات
      //   كدواء (رينجر فيه كالسيوم ← سيفترياكسون ...) ونفحص التوافق جوه نفس الكيس.
      var extraId = 1000;
      final fluidSnaps = <MedSnapshot>[];
      final bagItems = <({MedSnapshot fluid, MedSnapshot additive})>[];
      var fluidId = 5000;
      for (final f in p.fluids) {
        final def = fluidById(f.fluidId);
        final bagFluid = def == null ? null : fluidSnapshot(def, id: fluidId++);
        if (bagFluid != null && bagFluid.genericTokens.isNotEmpty) {
          fluidSnaps.add(bagFluid);
        }
        final bagAdds = <MedSnapshot>[];
        for (final a in f.additives) {
          final snap = additiveSnapshot(a.med, extraId++);
          snapshots.add(snap);
          if (bagFluid != null && bagFluid.genericTokens.isNotEmpty) {
            bagItems.add((fluid: bagFluid, additive: snap));
          }
          // نفس الكيس: كل إضافة مع اللي قبلها
          for (final prev in bagAdds) {
            bagItems.add((fluid: prev, additive: snap));
          }
          bagAdds.add(snap);
        }
      }

      // ✅ ids التشخيصات المخزّنة + الحل بالاسم (للمرضى القدام اللي ids بتاعتهم
      // ناقصة) + تشخيصات الأعراض المطابقة بالاسم (Cough ↔ Cough...)
      final dxNames = {...p.primaryDiagnoses, ...p.finalDiagnoses}.toList();
      final diagIds = {
        ...p.primaryDiagnosisIds,
        ...p.finalDiagnosisIds,
        ...await LocalDbService.instance.resolveDiagnosisIds(dxNames),
        ...await LocalDbService.instance.diagnosisIdsForSymptoms(p.symptoms),
      }.toList();
      await _loadLabs(p, diagIds, snapshots);

      // الـ patterns بتتجاب مرة عند التحميل وبتتعاد استخدامها بعد كده
      // (بتخلّي التنبيه بعد حفظ تحليل سريع)
      if (_refetchPatterns || !_patternsLoaded) {
        _refetchPatterns = false;
        try {
          _patterns =
              await PatientRepository.instance.fetchLocalPatterns(p.hospitalId);
          _patternsLoaded = true;
        } catch (e) {
          debugPrint('fetchLocalPatterns error: $e');
        }
      }

      final patientSnap = PatientSnapshot(
          age: p.age,
          weightKg: p.weightKg,
          diagnosisIds: diagIds,
          diagnosisNames: [...dxNames, ...p.symptoms],
          allergies: p.allergies
              .map((a) => PatientAllergyInfo(
                    label: a.className ?? a.drugName,
                    tokens: a.allergenTokens,
                  ))
              .toList(),
          herbNames: p.herbs.map((h) => h.name).toList(),
          comorbidities: p.comorbidities,
          hasCkd: p.comorbidities.any(isCkdName),
          hasLiverDisease: p.comorbidities.any(isLiverDiseaseName),
          sex: p.sex,
          isPregnant: p.isPregnant,
          labs: p.labResults
              .map((r) => LabResultSnapshot(
                    code: r.labCode,
                    name: r.labName,
                    unit: r.unit,
                    value: r.value,
                    abnormal: r.abnormal,
                    takenAt: r.takenAt,
                  ))
              .toList(),
        );
      final baseAlertsRaw = await AlertEngine.instance.analyze(
        patient: patientSnap,
        medications: snapshots,
        fluids: fluidSnaps,
        localPatterns: _patterns,
      );

      // عدم التوافق جوه الكيس (أخطر من التداخل العام): بنعرضه بدل نفس التنبيه
      // العام للزوج ده عشان ما يتكررش.
      final bagAlerts = await AlertEngine.instance
          .checkAdditiveCompatibility(bagItems, patient: patientSnap);
      String pairKey(String? a, String? b) {
        final x = (a ?? '').toLowerCase(), y = (b ?? '').toLowerCase();
        return x.compareTo(y) <= 0 ? '$x|$y' : '$y|$x';
      }
      final bagPairs = {for (final a in bagAlerts) pairKey(a.drugA, a.drugB)};
      final baseAlerts = baseAlertsRaw
          .where((a) =>
              !(a.typeCode == '5.3' && bagPairs.contains(pairKey(a.drugA, a.drugB))))
          .toList();
      final fluidWarnings = <({String fluid, String drug, String warning})>[
        for (final f in p.fluids)
          for (final a in f.additives)
            if (a.ivWarning != null)
              (fluid: f.name, drug: a.med.brandName, warning: a.ivWarning!),
      ];
      alerts.value = [
        ...AlertEngine.instance.checkFluidAdditives(fluidWarnings),
        ...bagAlerts,
        ...baseAlerts,
      ];
    } catch (e) {
      debugPrint('computeAlerts error: $e'); // السبينر بيتقفل في refreshAlerts
    }
  }

  /// التحاليل المقترحة (تشخيصات + أدوية) + المدى الطبيعي لكل تحليل (سن/جنس/حمل)
  Future<void> _loadLabs(
      PatientModel p, List<int> diagIds, List<MedSnapshot> meds) async {
    try {
      final db = LocalDbService.instance;
      final recs = await db.getRecommendedLabsFor(
        diagnosisIds: diagIds,
        drugTokens: meds
            .map((m) =>
                MedTokens(label: m.brandName, genericTokens: m.genericTokens))
            .toList(),
      );
      final tests = <String, LabTest>{for (final r in recs) r.lab.code: r.lab};
      for (final res in p.labResults) {
        if (!tests.containsKey(res.labCode)) {
          final l = await db.getLabByCode(res.labCode);
          if (l != null) tests[res.labCode] = l;
        }
      }
      final ranges = <String, LabRange?>{};
      for (final c in tests.keys) {
        ranges[c] = await db.getReferenceRange(c,
            age: p.age, sex: p.sex, isPregnant: p.isPregnant);
      }
      recommendedLabs.value = recs;
      labTests.assignAll(tests);
      labRanges.assignAll(ranges);
    } catch (e) {
      debugPrint('_loadLabs error: $e');
    }
  }

  // حفظات التحاليل بتتنفّذ واحدة ورا التانية (عشان مفيش نتيجة تضيع)
  Future<void> _labLock = Future.value();

  Future<void> _mutateLabs(
      List<LabResultModel> Function(List<LabResultModel> cur) change) {
    final run = _labLock.then((_) async {
      final p = patient.value;
      if (p == null) return;
      final list = change(p.labResults);
      if (identical(list, p.labResults)) return; // مفيش تغيير
      // لو الحفظ فشل الـ exception بتطلع للـ UI (الديالوج بيعرض رسالة الخطأ)
      await PatientRepository.instance.updateLabResults(patientId, list);
      // نطبّق على آخر نسخة (مش النسخة اللي قبل الـ await)
      final cur = patient.value;
      if (cur != null) patient.value = cur.copyWith(labResults: list);
      refreshAlerts(); // تنبيهات فورية بعد الحفظ
    });
    _labLock = run.catchError((_) {});
    return run;
  }

  Future<void> addLabResult(LabResultModel r) =>
      _mutateLabs((cur) => [...cur, r]);

  Future<void> removeLabResult(LabResultModel r) => _mutateLabs((cur) {
        final i = cur.indexWhere((x) =>
            x.labCode == r.labCode &&
            x.takenAt.isAtSameMomentAs(r.takenAt) &&
            x.value == r.value &&
            x.abnormal == r.abnormal);
        if (i < 0) return cur;
        return [...cur]..removeAt(i);
      });

  /// رجوع آمن: لو فيه صفحة قبلها يرجع، وإلا يروح للرئيسية
  void leave() {
    if (Get.key.currentState?.canPop() ?? false) {
      Get.back();
    } else {
      Get.offAllNamed('/home');
    }
  }

  Future<void> discharge() async {
    await PatientRepository.instance.discharge(patientId);
    if (Get.isRegistered<PatientsController>()) {
      PatientsController.to.markDirty(); // قايمة المرضى تتحدّث فوراً
    }
    leave();
  }

  Future<void> addIntervention(InterventionModel iv) async {
    await InterventionRepository.instance.addIntervention(iv);
    await reloadInterventions();
  }

  Future<void> addFollowUp(String id, String text) async {
    await InterventionRepository.instance.addFollowUp(id: id, text: text);
    await reloadInterventions();
  }

  /// قبول سريع: الأدمن بيقبل تدخلاته هو بنفسه (بدل ما يستنى رد الطبيب)
  Future<void> acceptOwnIntervention(String id) async {
    await InterventionRepository.instance.respondAsDoctor(
      id: id,
      response: 'accepted',
      doctor: AuthController.to.user,
    );
    await reloadInterventions();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class PatientFileScreen extends StatelessWidget {
  final String patientId;
  const PatientFileScreen({super.key, required this.patientId});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(PatientFileController(patientId), tag: patientId);

    return Obx(() {
      final p = ctrl.patient.value;
      if (p == null) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded),
              tooltip: 'رجوع',
              onPressed: ctrl.leave,
            ),
          ),
          body: Center(
            child: ctrl.loadError.value.isEmpty
                ? const CircularProgressIndicator()
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_rounded,
                            size: 56, color: AppColors.danger),
                        const SizedBox(height: 12),
                        Text(ctrl.loadError.value,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecond)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: ctrl.load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      }

      return DefaultTabController(
        length: 5,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded),
              tooltip: 'رجوع',
              onPressed: ctrl.leave,
            ),
            title: Text(p.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'تعديل بيانات المريض',
                onPressed: () async {
                  final saved = await Get.to<bool>(() => EditPatientScreen(
                        patient: p,
                        interventions: ctrl.interventions.toList(),
                        alerts: ctrl.alerts.toList(),
                      ));
                  if (saved == true) ctrl.load(); // بيانات + تنبيهات + تدخلات جديدة
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'تحديث',
                onPressed: ctrl.load,
              ),
              if (p.isActive)
                IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  tooltip: 'تسجيل خروج المريض',
                  onPressed: () => _confirmDischarge(context, ctrl),
                ),
            ],
            bottom: TabBar(
              onTap: ctrl.tabIndex.call,
              // التاب النشط: أبيض ساطع + خط عريض + مؤشر سميك
              // التاب غير النشط: أبيض باهت (واضح على الخلفية الزرقاء)
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withOpacity(0.6),
              indicatorColor: Colors.white,
              indicatorWeight: 4,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.white24,
              labelStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                  fontSize: 15),
              unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w500,
                  fontSize: 14),
              tabs: [
                const Tab(
                    text: 'البيانات',
                    icon: Icon(Icons.person_outline_rounded, size: 18)),
                const Tab(
                    text: 'الأدوية',
                    icon: Icon(Icons.medication_outlined, size: 18)),
                const Tab(
                    text: 'التحاليل',
                    icon: Icon(Icons.biotech_outlined, size: 18)),
                Tab(
                  child: Obx(() => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.edit_note_rounded, size: 18),
                          const SizedBox(width: 4),
                          const Text('تدخلات'),
                          if (ctrl.interventions.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            _Badge(ctrl.interventions.length.toString()),
                          ],
                        ],
                      )),
                ),
                Tab(
                  child: Obx(() => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 18),
                          const SizedBox(width: 4),
                          const Text('تنبيهات'),
                          if (ctrl.alerts.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            _Badge(ctrl.alerts.length.toString(),
                                color: ctrl.alerts.any((a) =>
                                        a.severity == AlertSeverity.major)
                                    ? AppColors.danger
                                    : AppColors.warning),
                          ],
                        ],
                      )),
                ),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _InfoTab(patient: p),
              _MedsTab(patient: p, ctrl: ctrl),
              _LabsTabHost(ctrl: ctrl),
              _InterventionsTab(ctrl: ctrl),
              _AlertsTab(ctrl: ctrl),
            ],
          ),
        ),
      );
    });
  }

  void _confirmDischarge(BuildContext ctx, PatientFileController ctrl) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('تسجيل خروج المريض',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        content: const Text('هل تريد تسجيل خروج المريض وإغلاق الملف؟',
            style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Get.back();
              ctrl.discharge();
            },
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  TAB 1 — البيانات
// ─────────────────────────────────────────────────────────────────────────────
class _InfoTab extends StatelessWidget {
  final PatientModel patient;
  const _InfoTab({required this.patient});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(title: 'البيانات الأساسية', rows: [
            _Row('الاسم', patient.name),
            _Row('السن', patient.ageText),
            if (patient.sex != null)
              _Row('الجنس',
                  '${patient.sex == 'F' ? 'أنثى' : 'ذكر'}${patient.sex == 'F' && patient.isPregnant ? ' (حامل)' : ''}'),
            if (patient.weightKg != null)
              _Row('الوزن', '${patient.weightKg!.toStringAsFixed(1)} kg'),
            _Row('رقم الملف', patient.fileNumber),
            _Row('تاريخ الدخول', patient.displayAdmission),
            _Row('أضافه', patient.addedByUserName),
          ]),
          const SizedBox(height: 12),
          _InfoCard(title: 'الأعراض والتشخيص', rows: [
            if (patient.symptoms.isNotEmpty)
              _Row('الأعراض', patient.symptoms.join('، ')),
            // مرضى قدام اتسجلوا بتشخيص مبدئي
            if (patient.primaryDiagnoses.isNotEmpty)
              _Row('المبدئي', patient.primaryDiagnoses.join('، ')),
            if (patient.finalDiagnoses.isNotEmpty)
              _Row('النهائي', patient.finalDiagnoses.join('، ')),
          ]),
          const SizedBox(height: 12),
          if (patient.hasComorbidities)
            _InfoCard(title: 'الأمراض المزمنة', rows: [
              _Row('', patient.comorbidities.join('، ')),
            ]),
          if (patient.hasAllergies) ...[
            const SizedBox(height: 12),
            _InfoCard(
              title: '⚠️ الحساسية',
              titleColor: AppColors.warning,
              rows: patient.allergies
                  .map((a) => _Row(a.drugName, a.reactionType))
                  .toList(),
            ),
          ],
          if (patient.hasHerbs && patient.herbs.isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoCard(
              title: '🌿 أعشاب/مكملات',
              titleColor: AppColors.success,
              rows: [_Row('', patient.herbs.map((h) => h.name).join('، '))],
            ),
          ],
        ],
      );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Color? titleColor;
  final List<Widget> rows;
  const _InfoCard({required this.title, required this.rows, this.titleColor});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: titleColor ?? AppColors.primary)),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...rows,
            ],
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  final String label, value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label.isNotEmpty) ...[
              SizedBox(
                width: 110,
                child: Text(label,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: AppColors.textSecond)),
              ),
            ],
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  TAB 2 — الأدوية
// ─────────────────────────────────────────────────────────────────────────────
class _MedsTab extends StatelessWidget {
  final PatientModel patient;
  final PatientFileController ctrl;
  const _MedsTab({required this.patient, required this.ctrl});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (patient.prescribedMedications.isNotEmpty) ...[
            _MedSection('الأدوية الموصوفة', patient.prescribedMedications,
                color: AppColors.primary),
            const SizedBox(height: 16),
          ],
          if (patient.chronicMedications.isNotEmpty)
            _MedSection('الأدوية المزمنة', patient.chronicMedications,
                color: AppColors.textSecond),
          if (patient.fluids.isNotEmpty) ...[
            const SizedBox(height: 16),
            _FluidsSection(patient.fluids),
          ],
          if (patient.prescribedMedications.isEmpty &&
              patient.chronicMedications.isEmpty &&
              patient.fluids.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text('لا توجد أدوية مسجّلة',
                    style: TextStyle(
                        fontFamily: 'Cairo', color: AppColors.textSecond)),
              ),
            ),
        ],
      );
}

class _FluidsSection extends StatelessWidget {
  final List<FluidOrder> fluids;
  const _FluidsSection(this.fluids);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('المحاليل الوريدية',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.info)),
          const SizedBox(height: 8),
          ...fluids.map((f) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.water_drop_rounded,
                            color: AppColors.info, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(f.name,
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14))),
                      ]),
                      for (final a in f.additives)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, right: 28),
                          child: Row(children: [
                            Icon(
                                a.ivWarning != null
                                    ? Icons.warning_amber_rounded
                                    : Icons.add_circle_outline_rounded,
                                size: 16,
                                color: a.ivWarning != null
                                    ? AppColors.warning
                                    : AppColors.textSecond),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(
                                    '${a.med.brandName} ${a.med.strength} — ${a.med.form}',
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                        color: AppColors.textSecond))),
                          ]),
                        ),
                    ],
                  ),
                ),
              )),
        ],
      );
}

class _MedSection extends StatelessWidget {
  final String title;
  final List<MedicationModel> meds;
  final Color color;
  const _MedSection(this.title, this.meds, {required this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: color)),
          const SizedBox(height: 8),
          ...meds.map((m) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.1),
                    child:
                        Icon(Icons.medication_rounded, color: color, size: 20),
                  ),
                  title: Text(m.brandName,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  subtitle: Text('${m.genericName} — ${m.strength} — ${m.form}',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.textSecond)),
                  trailing: Text(m.frequency,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
              )),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  TAB 3 — التدخلات
// ─────────────────────────────────────────────────────────────────────────────
class _InterventionsTab extends StatelessWidget {
  final PatientFileController ctrl;
  const _InterventionsTab({required this.ctrl});

  @override
  Widget build(BuildContext context) => Obx(() {
        if (ctrl.interventions.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit_note_rounded,
                    size: 56, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                const Text('لا توجد تدخلات بعد',
                    style: TextStyle(
                        fontFamily: 'Cairo', color: AppColors.textSecond)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => _showAddInterventionSheet(context, ctrl),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة تدخل'),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: ctrl.interventions.length,
                itemBuilder: (_, i) => _InterventionCard(
                  iv: ctrl.interventions[i],
                  ctrl: ctrl,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showAddInterventionSheet(context, ctrl),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('إضافة تدخل جديد'),
                ),
              ),
            ),
          ],
        );
      });
}

class _InterventionCard extends StatelessWidget {
  final InterventionModel iv;
  final PatientFileController ctrl;
  const _InterventionCard({required this.iv, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.to;
    final isAdminRole = auth.user.isAdmin || auth.user.isSuperAdmin;
    // تدخل الأدمن بنفسه
    final isAdminOwn = isAdminRole && iv.addedByUserId == auth.user.id;
    final isPending = iv.doctorResponse == 'pending';
    final accent = isAdminOwn ? AppColors.adminOwn : AppColors.primary;

    return Card(
        color: isAdminOwn ? AppColors.adminOwn.withOpacity(0.05) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isAdminOwn
              ? const BorderSide(color: AppColors.adminOwn, width: 1.5)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  if (isAdminOwn) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
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
                  Text(iv.typeNameAr,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: AppColors.textSecond)),
                ],
              ),
              const SizedBox(height: 10),
              Text(iv.comment,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
              if (iv.extraNote != null && iv.extraNote!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('📝 ${iv.extraNote}',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.textSecond)),
              ],
              InterventionExtras(iv: iv),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: iv.responseColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(iv.responseLabel,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: iv.responseColor,
                            fontWeight: FontWeight.w600)),
                  ),
                  const Spacer(),
                  // قبول سريع — للأدمن على تدخلاته فقط ولو لسه معلّقة
                  if (isAdminOwn && isPending && iv.id != null)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.adminOwn,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                      onPressed: () => _acceptOwn(),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('قبول',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    ),
                  if ((iv.followUp ?? '').isEmpty &&
                      iv.id != null &&
                      iv.addedByUserId == AuthController.to.user.id)
                    TextButton.icon(
                      onPressed: () => _askFollowUp(context),
                      icon: const Icon(Icons.add_comment_outlined, size: 16),
                      label: const Text('إضافة متابعة',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    ),
                ],
              ),
              if (iv.doctorNote != null && iv.doctorNote!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      'ملاحظة الطبيب${iv.doctorName != null ? " (${iv.doctorName})" : ""}: ${iv.doctorNote}',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.textSecond)),
                ),
            ],
          ),
        ),
      );
  }

  Future<void> _acceptOwn() async {
    try {
      await ctrl.acceptOwnIntervention(iv.id!);
    } catch (e) {
      Get.snackbar('تعذّر القبول', '$e');
    }
  }

  Future<void> _askFollowUp(BuildContext context) async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('متابعة التدخل',
            style: TextStyle(fontFamily: 'Cairo')),
        content: TextField(
          controller: c,
          maxLines: 4,
          maxLength: 1000,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
              hintText: 'اكتب نتيجة المتابعة (تتسجل مرة واحدة)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo'))),
        ],
      ),
    );
    c.dispose();
    if (text == null || text.isEmpty || iv.id == null) return;
    try {
      await ctrl.addFollowUp(iv.id!, text);
    } catch (_) {
      Get.snackbar('تعذّر الحفظ', 'المتابعة اتسجلت قبل كده أو مفيش صلاحية');
    }
  }

}

// ─────────────────────────────────────────────────────────────────────────────
//  TAB 4 — التنبيهات
// ─────────────────────────────────────────────────────────────────────────────
class _AlertsTab extends StatelessWidget {
  final PatientFileController ctrl;
  const _AlertsTab({required this.ctrl});

  @override
  Widget build(BuildContext context) => Obx(() {
        final analyzing = ctrl.isAnalyzing.value;
        if (analyzing && ctrl.alerts.isEmpty) {
          return const Center(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('جاري تحليل الأدوية...',
                  style: TextStyle(fontFamily: 'Cairo')),
            ],
          ));
        }
        if (ctrl.alerts.isEmpty) {
          return const Center(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  size: 56, color: Color(0xFF22C55E)),
              SizedBox(height: 12),
              Text('لا توجد تنبيهات — الأدوية سليمة ✅',
                  style:
                      TextStyle(fontFamily: 'Cairo', color: Color(0xFF22C55E))),
            ],
          ));
        }
        return Column(
          children: [
            if (analyzing) const LinearProgressIndicator(minHeight: 3),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: ctrl.alerts.length,
                itemBuilder: (_, i) =>
                    _AlertCard(alert: ctrl.alerts[i], ctrl: ctrl),
              ),
            ),
          ],
        );
      });
}

class _AlertCard extends StatefulWidget {
  final ClinicalAlert alert;
  final PatientFileController ctrl;
  const _AlertCard({required this.alert, required this.ctrl});

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _expanded = false; // الوضع الافتراضي: مصغّر

  ClinicalAlert get alert => widget.alert;
  PatientFileController get ctrl => widget.ctrl;

  Color get _borderColor => switch (alert.severity) {
        AlertSeverity.major => AppColors.danger,
        AlertSeverity.moderate => AppColors.warning,
        AlertSeverity.minor => AppColors.info,
        AlertSeverity.info => AppColors.textSecond,
      };

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border(right: BorderSide(color: _borderColor, width: 4)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _borderColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(alert.severityLabel,
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            color: _borderColor,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(alert.typeCode,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(alert.title,
                        maxLines: _expanded ? null : 2,
                        overflow: _expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(alert.body,
                        maxLines: _expanded ? null : 2,
                        overflow: _expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: AppColors.textSecond)),
                  ],
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                      _expanded
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                      size: 16),
                  label: Text(_expanded ? 'تصغير' : 'تكبير',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              if (alert.autoSuggestIntervention) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showAddInterventionSheet(context, ctrl, alert: alert),
                    icon: const Icon(Icons.add_task_rounded, size: 16),
                    label: const Text('تسجيل تدخل',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  ADD INTERVENTION BOTTOM SHEET  (حقول ديناميكية حسب نوع التدخل)
// ─────────────────────────────────────────────────────────────────────────────
void _showAddInterventionSheet(
  BuildContext context,
  PatientFileController ctrl, {
  ClinicalAlert? alert,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddInterventionSheet(ctrl: ctrl, alert: alert),
  );
}

const _formAr = {
  'Tablet': 'قرص',
  'Capsule': 'كبسولة',
  'Vial': 'فيال',
  'Syrup': 'شراب',
  'Infusion': 'محلول وريدي',
  'Ampoule': 'أمبول',
};

class _AddInterventionSheet extends StatefulWidget {
  final PatientFileController ctrl;
  final ClinicalAlert? alert;
  const _AddInterventionSheet({required this.ctrl, this.alert});
  @override
  State<_AddInterventionSheet> createState() => _AddInterventionSheetState();
}

class _AddInterventionSheetState extends State<_AddInterventionSheet> {
  InterventionType? _selected;
  final Map<String, String> _v = {}; // DRUG / ALT / OLD / NEW / CONDITION / REASON
  List<String> _formSuggestions = [];
  final Map<String, String> _genByName = {}; // قيمة الحقل (من الـ picker) → نص التعليق: generic + تركيز + شكل + تكرار
  final _extraCtrl = TextEditingController();
  String _comment = '';
  bool _saving = false;
  final _refCtrl = TextEditingController();
  final _refFocus = FocusNode();
  List<String> _refSuggestions = [];
  String _deptName = '';
  // true = القيمة لسه مقترحة من التطبيق (لو المستخدم غيّرها بنبطّل نغيّرها)
  bool _refAuto = true,
      _stageAuto = true,
      _descAuto = true,
      _actionAuto = true,
      _causeAuto = true,
      _sevAuto = true;
  bool _isErr = false;
  String? _errStage, _errCause, _errSev;
  final _errDescCtrl = TextEditingController();
  final _errActionCtrl = TextEditingController();

  PatientModel get _p => widget.ctrl.patient.value!;
  List<MedicationModel> get _all =>
      [..._p.prescribedMedications, ..._p.chronicMedications];
  String _label(MedicationModel m) => '${m.brandName} ${m.strength}'.trim();
  List<VarSpec> get _specs => _selected == null
      ? const []
      : (kInterventionFields[_selected!.code] ?? const []);

  @override
  void initState() {
    super.initState();
    _loadDeptName();
    final a = widget.alert;
    if (a != null) {
      _selected = findInterventionByCode(a.typeCode);
      _applyAlert(a);
      _rebuildComment();
    }
  }

  @override
  void dispose() {
    _extraCtrl.dispose();
    _errDescCtrl.dispose();
    _refCtrl.dispose();
    _refFocus.dispose();
    _errActionCtrl.dispose();
    super.dispose();
  }

  // ── ملء تلقائي من التنبيه ─────────────────────────────────────────
  /// بيطابق اسم الدواء في التنبيه (تجاري أو علمي) على دواء المريض.
  /// لو مفيش تطابق (زي العشب) بيرجّع الاسم كما هو ويظهر كنص مخصص.
  String _matchMed(String name) {
    final l = name.toLowerCase().trim();
    for (final m in _all) {
      final tokens = m.normalizedGenerics
          .split('|')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty);
      if (m.brandName.toLowerCase() == l ||
          m.genericName.toLowerCase() == l ||
          tokens.contains(l)) {
        return _label(m);
      }
    }
    return name;
  }

  void _applyAlert(ClinicalAlert a) {
    final tokens = _specs.map((s) => s.token).toSet();
    if (tokens.contains('DRUG') && a.drugA != null) {
      _v['DRUG'] = _matchMed(a.drugA!);
    }
    if (tokens.contains('ALT') && a.drugB != null) {
      _v['ALT'] = _matchMed(a.drugB!);
    }
    if (tokens.contains('REASON') && a.reason != null) {
      _v['REASON'] = a.reason!;
    }
    _onDrugChanged();
  }

  // ── الاختيارات حسب المصدر ─────────────────────────────────────────
  List<String> _options(VarSpec s) {
    switch (s.source) {
      case FieldSource.prescribed:
        return _p.prescribedMedications.map(_label).toSet().toList();
      case FieldSource.allMeds:
        return _all.map(_label).toSet().toList();
      case FieldSource.otherMeds:
        final meds =
            _all.map(_label).toSet().where((l) => l != _v['DRUG']).toList();
        // في التداخلات: الأعشاب اللي المريض بياخدها ممكن تكون الطرف التاني
        if (_selected?.code == '3.0') {
          meds.addAll(_p.herbs.map((h) => h.name));
        }
        return meds;
      case FieldSource.recommendation:
        final a = _v['DRUG'];
        final b = _v['ALT'];
        return [
          if (a != null && a.isNotEmpty) 'إيقاف $a',
          if (b != null && b.isNotEmpty) 'إيقاف $b',
          if (a != null && a.isNotEmpty) 'تغيير $a لبديل أنسب',
          if (b != null && b.isNotEmpty) 'تغيير $b لبديل أنسب',
        ];
      case FieldSource.condition:
        return {
          ..._p.primaryDiagnoses,
          ..._p.finalDiagnoses,
          ..._p.comorbidities,
          ..._p.symptoms,
        }.toList();
      case FieldSource.form:
        return {..._formSuggestions, ...kDosageForms}.toList();
      default:
        return const [];
    }
  }

  // ── لما الدواء الأول يتغير ────────────────────────────────────────
  void _onDrugChanged() {
    final label = _v['DRUG'];
    final med = _all.where((m) => _label(m) == label).firstOrNull;
    if (_v['ALT'] == label) _v.remove('ALT');
    if (med == null) return;

    final code = _selected?.code;
    if (code == '2.3' || code == '7.6') {
      _v['OLD'] = med.form;
      _loadFormSuggestions(med);
    } else if (code == '4.1') {
      _v['OLD'] = '${med.strength} ${med.frequency}'.trim();
    }
  }

  /// اقتراح نفس الدواء بأشكال تانية من الـ DB
  Future<void> _loadFormSuggestions(MedicationModel med) async {
    final db = LocalDbService.instance;
    final rows = <DrugSearchResult>[
      ...await db.getStrengthsForBrand(med.brandName),
      if (med.genericName.isNotEmpty) ...await db.searchDrugs(med.genericName),
    ];
    final gen = med.genericName.toLowerCase();
    final forms = rows
        .where((r) => r.genericName.toLowerCase() == gen)
        .map((r) => _formAr[r.form] ?? r.form)
        .where((f) => f.isNotEmpty && f != med.form)
        .toSet()
        .toList();
    if (mounted) setState(() => _formSuggestions = forms);
  }

  void _onTypeChanged(InterventionType? t) {
    setState(() {
      _selected = t;
      _v.clear();
      _formSuggestions = [];
      final a = widget.alert;
      if (a != null && a.typeCode == t?.code) _applyAlert(a);
    });
    _rebuildComment();
  }

  void _set(String token, String value) {
    _v[token] = value;
    if (_selected?.code == '3.0' && (token == 'DRUG' || token == 'ALT')) {
      _v.remove('NEW'); // التوصية بتعتمد على الدواءين
    }
    if (token == 'DRUG') _onDrugChanged();
    _rebuildComment();
  }

  /// الاسم العلمي (generic) للقيمة المختارة في حقل دواء — للتعليق فقط.
  String? _genericOf(String? label) {
    if (label == null || label.trim().isEmpty) return null;
    final med = _all.where((m) => _label(m) == label).firstOrNull;
    if (med != null && med.genericName.trim().isNotEmpty) {
      return med.genericName.trim();
    }
    final g = _genByName[label.trim()];
    if (g != null && g.trim().isNotEmpty) return g.trim();
    return label.trim(); // عشب أو اسم مكتوب يدويًا
  }

  /// نص التوصية في التداخل: نبدّل اسم كل دواء بالـ generic بتاعه
  String? _recForComment() {
    var r = _val('NEW');
    if (r == null || _selected?.code != '3.0') return r;
    for (final t in ['DRUG', 'ALT']) {
      final label = _v[t];
      final g = _genericOf(label);
      if (label != null && label.isNotEmpty && g != null) {
        r = r!.replaceAll(label, g);
      }
    }
    return r;
  }

  Future<void> _loadDeptName() async {
    try {
      final list = await OrgRepository.instance.departments(_p.hospitalId);
      final d = list.where((e) => e.id == _p.departmentId);
      if (d.isNotEmpty && mounted) {
        _deptName = d.first.name;
        setState(_applySuggestions);
      }
    } catch (_) {/* الاقتراح بيشتغل بالسن والتشخيص بس */}
  }

  /// بيملى كل الحقول المقترحة (اللى المستخدم ماغيّرهاش)
  void _applySuggestions() {
    final s = _selected;
    if (s == null) return;
    _refSuggestions = InterventionSuggester.references(
      deptName: _deptName,
      age: _p.age,
      diagnoses: [..._p.primaryDiagnoses, ..._p.finalDiagnoses],
      typeCode: s.code,
    );
    if (_refAuto && _refSuggestions.isNotEmpty) {
      _refCtrl.text = _refSuggestions.first;
    }
    if (!_isErr) return;
    if (_stageAuto) _errStage = InterventionSuggester.stage(s.code);
    if (_causeAuto) _errCause = InterventionSuggester.cause(s.code, _p.age);
    if (_sevAuto) _errSev = InterventionSuggester.severity(s.code);
    final letter = (_errSev ?? 'B').substring(0, 1);
    if (_descAuto) {
      _errDescCtrl.text = InterventionSuggester.description(
        typeNameAr: s.nameAr,
        comment: _comment,
        stage: _errStage,
        severityLetter: letter,
      );
    }
    if (_actionAuto) {
      _errActionCtrl.text = InterventionSuggester.action(s.nameAr);
    }
  }

  String? _val(String t) =>
      (_v[t]?.trim().isEmpty ?? true) ? null : _v[t]!.trim();

  void _rebuildComment() {
    if (_selected == null) return;
    setState(() {
      _comment = InterventionModel.buildComment(
        template: _selected!.code == '3.0'
            ? 'تم التدخل بخصوص التداخل الدوائي بين [DRUG] و[ALT] '
                'والتوصية بـ [NEW] وذلك بسبب [REASON]'
            : _selected!.commentTemplate,
        drug: _genericOf(_val('DRUG')),
        alt: _genericOf(_val('ALT')),
        old: _val('OLD'),
        newVal: _recForComment(),
        condition: _val('CONDITION'),
        reason: _val('REASON'),
      );
      _applySuggestions();
    });
  }

  bool get _canSave =>
      _selected != null &&
      _specs.where((s) => s.isRequired).every((s) => _val(s.token) != null) &&
      (!_isErr ||
          (_errStage != null &&
              _errSev != null &&
              _errDescCtrl.text.trim().isNotEmpty));

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final auth = AuthController.to;
    final iv = InterventionModel(
      patientId: widget.ctrl.patientId,
      hospitalId: _p.hospitalId,
      departmentId: _p.departmentId,
      addedByUserId: auth.user.id,
      addedByUserName: auth.user.name,
      typeCode: _selected!.code,
      categoryAr: _selected!.categoryAr,
      typeNameEn: _selected!.nameEn,
      typeNameAr: _selected!.nameAr,
      drugName: _val('DRUG'),
      altDrugName: _val('ALT'),
      oldValue: _val('OLD'),
      newValue: _val('NEW'),
      conditionName: _val('CONDITION'),
      reason: _val('REASON'),
      comment: _comment,
      extraNote:
          _extraCtrl.text.trim().isEmpty ? null : _extraCtrl.text.trim(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      reference: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
      isMedError: _isErr,
      errorStage: _isErr ? _errStage : null,
      errorDescription: _isErr ? _errDescCtrl.text.trim() : null,
      errorAction: _isErr && _errActionCtrl.text.trim().isNotEmpty
          ? _errActionCtrl.text.trim()
          : null,
      errorCause: _isErr ? _errCause : null,
      errorSeverity: _isErr ? _errSev : null,
    );
    await widget.ctrl.addIntervention(iv);
    if (mounted) Navigator.pop(context);
  }

  Widget _errDrop(String label, List<String> items, String? value,
          ValueChanged<String?> onChanged) =>
      DropdownButtonFormField<String>(
        value: items.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label, filled: true, fillColor: Colors.white),
        items: items
            .map((e) => DropdownMenuItem(
                value: e,
                child: Text(e,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Colors.black87))))
            .toList(),
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scroll) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF5F7FA),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.all(20),
            children: [
              // Handle
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('إضافة تدخل إكلينيكي',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),

              // اختيار النوع
              DropdownButtonFormField<InterventionType>(
                value: _selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'نوع التدخل',
                  filled: true,
                  fillColor: Colors.white,
                ),
                items: kInterventionTypes
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text('${t.code} — ${t.nameAr}',
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: Colors.black87)),
                        ))
                    .toList(),
                onChanged: _onTypeChanged,
              ),
              const SizedBox(height: 16),

              if (_selected != null) ...[
                // ── الحقول المناسبة للنوع فقط ───────────────────────
                for (final s in _specs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _VarInput(
                      key: ValueKey('${_selected!.code}_${s.token}'),
                      spec: s,
                      options: _options(s),
                      value: _v[s.token] ?? '',
                      onChanged: (val) => _set(s.token, val),
                      onGeneric: (brand, gen) => _genByName[brand] = gen,
                    ),
                  ),

                // ── معاينة التعليق ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📋 التعليق:',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                      const SizedBox(height: 6),
                      TextFormField(
                        key: ValueKey(_comment),
                        initialValue: _comment,
                        textDirection: TextDirection.rtl,
                        maxLines: 3,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            color: Colors.black87),
                        decoration: const InputDecoration(
                            border: InputBorder.none, isDense: true),
                        onChanged: (v) => _comment = v,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _extraCtrl,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 13, color: Colors.black87),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة إضافية (اختياري)',
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                RawAutocomplete<String>(
                  textEditingController: _refCtrl,
                  focusNode: _refFocus,
                  optionsBuilder: (v) {
                    final q = v.text.trim().toLowerCase();
                    if (q.isEmpty) return _refSuggestions;
                    return kReferences
                        .where((r) => r.toLowerCase().contains(q))
                        .take(8);
                  },
                  fieldViewBuilder: (ctx, c, fn, _) => TextField(
                    controller: c,
                    focusNode: fn,
                    onChanged: (_) => _refAuto = false,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.black87),
                    decoration: const InputDecoration(
                      labelText: 'المرجع العلمي (مقترح — غيّره لو عايز)',
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  optionsViewBuilder: (ctx, onSel, opts) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView(
                          shrinkWrap: true,
                          children: opts
                              .map((o) => ListTile(
                                    dense: true,
                                    title: Text(o,
                                        style: const TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12)),
                                    onTap: () {
                                      _refAuto = false;
                                      onSel(o);
                                    },
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_refSuggestions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _refSuggestions
                          .map((r) => ActionChip(
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: Colors.black26),
                                label: Text(r.split(' (').first,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        color: Colors.black,
                                        fontWeight: FontWeight.w600)),
                                onPressed: () => setState(() {
                                  _refAuto = false;
                                  _refCtrl.text = r;
                                }),
                              ))
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('هل ده كمان خطأ دوائي؟',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                  value: _isErr,
                  onChanged: (v) => setState(() {
                    _isErr = v;
                    if (v) _applySuggestions();
                  }),
                ),
                if (_isErr) ...[
                  _errDrop('مرحلة/نوع الخطأ', kErrorStages, _errStage,
                      (v) => setState(() {
                        _stageAuto = false;
                        _errStage = v;
                      })),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _errDescCtrl,
                    maxLines: 2,
                    maxLength: 2000,
                    onChanged: (_) => setState(() => _descAuto = false),
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(
                        labelText: 'وصف الخطأ (مقترح — عدّله)',
                        filled: true,
                        fillColor: Colors.white),
                  ),
                  TextField(
                    controller: _errActionCtrl,
                    maxLines: 2,
                    maxLength: 2000,
                    onChanged: (_) => _actionAuto = false,
                    textDirection: TextDirection.rtl,
                    decoration: const InputDecoration(
                        labelText: 'إجراء الصيدلاني (اختياري)',
                        filled: true,
                        fillColor: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  _errDrop('السبب المحتمل (مقترح)', kErrorCauses, _errCause,
                      (v) => setState(() {
                        _causeAuto = false;
                        _errCause = v;
                      })),
                  const SizedBox(height: 10),
                  _errDrop('الخطورة A–I (مقترحة)', kErrorSeverities, _errSev,
                      (v) => setState(() {
                        _sevAuto = false;
                        _errSev = v;
                      })),
                ],
              ],

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving || !_canSave ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('حفظ التدخل',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                              fontSize: 16)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  حقل ذكي: Chips (أدوية/حالات/أشكال) أو بحث DB أو نص حر
// ─────────────────────────────────────────────────────────────────────────────
class _VarInput extends StatefulWidget {
  final VarSpec spec;
  final List<String> options;
  final String value;
  final void Function(String) onChanged;
  final void Function(String brand, String generic)? onGeneric;
  const _VarInput({
    super.key,
    required this.spec,
    required this.options,
    required this.value,
    required this.onChanged,
    this.onGeneric,
  });
  @override
  State<_VarInput> createState() => _VarInputState();
}

class _VarInputState extends State<_VarInput> {
  late final TextEditingController _tc;
  bool _custom = false;

  bool get _chipsMode =>
      const {
        FieldSource.prescribed,
        FieldSource.allMeds,
        FieldSource.otherMeds,
        FieldSource.condition,
        FieldSource.form,
        FieldSource.recommendation,
      }.contains(widget.spec.source) &&
      widget.options.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _tc = TextEditingController(text: widget.value);
    _custom = widget.value.isNotEmpty && !widget.options.contains(widget.value);
  }

  @override
  void didUpdateWidget(covariant _VarInput old) {
    super.didUpdateWidget(old);
    if (_tc.text != widget.value) {
      // تعبئة تلقائية من الأب
      _tc.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  static const _chipText = TextStyle(
      fontFamily: 'Cairo', fontSize: 12, color: Colors.black87);
  static const _inputText =
      TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.black87);

  InputDecoration _dec([String? hint]) => InputDecoration(
      hintText: hint, filled: true, fillColor: Colors.white, isDense: true);

  @override
  Widget build(BuildContext context) {
    final s = widget.spec;
    Widget input;

    if (s.source == FieldSource.dbDrug) {
      input = _DrugPickerField(
        initialValue: widget.value,
        onPicked: (value, commentText) {
          widget.onGeneric?.call(value, commentText);
          widget.onChanged(value);
        },
        onClear: () => widget.onChanged(''),
      );
    } else if (_chipsMode) {
      input = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final o in widget.options)
                ChoiceChip(
                  label: Text(o, style: _chipText),
                  backgroundColor: Colors.white,
                  selectedColor: AppColors.primary.withOpacity(0.18),
                  checkmarkColor: AppColors.primary,
                  selected: !_custom && widget.value == o,
                  onSelected: (_) {
                    setState(() => _custom = false);
                    widget.onChanged(o);
                  },
                ),
              ChoiceChip(
                label: const Text('أخرى ✍️', style: _chipText),
                backgroundColor: Colors.white,
                selectedColor: AppColors.primary.withOpacity(0.18),
                checkmarkColor: AppColors.primary,
                selected: _custom,
                onSelected: (_) {
                  setState(() => _custom = true);
                  widget.onChanged('');
                },
              ),
            ],
          ),
          if (_custom) ...[
            const SizedBox(height: 8),
            TextField(
                controller: _tc,
                textDirection: TextDirection.rtl,
                style: _inputText,
                onChanged: widget.onChanged,
                decoration: _dec('اكتب هنا...')),
          ],
        ],
      );
    } else {
      input = TextField(
        controller: _tc,
        textDirection: TextDirection.rtl,
        maxLines: s.token == 'REASON' ? 2 : 1,
        style: _inputText,
        onChanged: widget.onChanged,
        decoration: _dec(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.label + (s.isRequired ? ' *' : ''),
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87)),
        const SizedBox(height: 6),
        input,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Drug Picker (زي صفحة إضافة المريض): بحث ← تركيز (بشكله من الـ DB) ← تكرار
//  القيمة بتتسجّل أول ما التركيز يتختار، والتكرار بعدها اختياري.
// ─────────────────────────────────────────────────────────────────────────────
class _DrugPickerField extends StatefulWidget {
  final String initialValue;

  /// value = النص المحفوظ (تجاري)، commentText = النص اللي يظهر في التعليق (generic)
  final void Function(String value, String commentText) onPicked;
  final VoidCallback onClear;
  const _DrugPickerField({
    required this.initialValue,
    required this.onPicked,
    required this.onClear,
  });
  @override
  State<_DrugPickerField> createState() => _DrugPickerFieldState();
}

class _DrugPickerFieldState extends State<_DrugPickerField> {
  final _tc = TextEditingController();
  List<DrugSearchResult> _results = [];
  List<DrugSearchResult> _strengths = [];
  DrugSearchResult? _strength; // التركيز المختار (بيحدد الدواء والشكل)
  String _freq = '';
  String _value = ''; // القيمة المسجلة حاليًا

  static const _txt =
      TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.black87);

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() {
        _results = [];
        _strengths = [];
      });
      return;
    }
    final r = await LocalDbService.instance.searchDrugs(q);
    if (mounted) setState(() => _results = r);
  }

  Future<void> _selectDrug(DrugSearchResult d) async {
    final st = await LocalDbService.instance.getStrengthsForBrand(d.brandName);
    if (!mounted) return;
    setState(() {
      _tc.text = d.brandName;
      _results = [];
      _strengths = st;
    });
  }

  /// تسجيل الدواء: بيتنادى أول ما التركيز يتختار وكل ما التكرار يتغير
  void _commit() {
    final s = _strength;
    if (s == null) return;
    final base = '${s.strength} ${s.form}'.trim();
    final gen =
        s.genericName.trim().isEmpty ? s.brandName : s.genericName.trim();
    final suffix = _freq.isEmpty ? '' : ' — $_freq';
    final value = '${s.brandName} $base$suffix';
    final commentText = '$gen $base$suffix';
    setState(() => _value = value);
    widget.onPicked(value, commentText);
  }

  void _clear() {
    setState(() {
      _value = '';
      _strength = null;
      _strengths = [];
      _results = [];
      _freq = '';
      _tc.clear();
    });
    widget.onClear();
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black87)),
      );

  @override
  Widget build(BuildContext context) {
    // ✅ دواء متسجّل → ملخص + التكرار (اختياري)
    if (_value.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.success.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_value,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: Colors.black87)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.danger),
                  tooltip: 'تغيير الدواء',
                  onPressed: _clear,
                ),
              ],
            ),
          ),
          if (_strength != null) ...[
            _label('التكرار (اختياري)'),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final f in kFrequencies)
                  ChoiceChip(
                    label: Text(f, style: _txt),
                    backgroundColor: Colors.white,
                    selectedColor: AppColors.primary.withOpacity(0.18),
                    checkmarkColor: AppColors.primary,
                    selected: _freq == f,
                    onSelected: (sel) {
                      _freq = sel ? f : '';
                      _commit();
                    },
                  ),
              ],
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // بحث
        TextField(
          controller: _tc,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
              fontFamily: 'Cairo', fontSize: 13, color: Colors.black87),
          onChanged: _search,
          decoration: const InputDecoration(
            hintText: 'ابحث بالاسم التجاري أو العلمي...',
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            prefixIcon: Icon(Icons.search_rounded, size: 18),
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = _results[i];
                return ListTile(
                  dense: true,
                  title: Text(d.brandName,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: Colors.black87)),
                  subtitle: Text(d.genericName,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.textSecond)),
                  trailing: Text(d.strength,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.primary)),
                  onTap: () => _selectDrug(d),
                );
              },
            ),
          ),

        // التركيز (الشكل الصيدلي جاي مع التركيز من الـ DB — مفيش اختيار منفصل)
        if (_strengths.isNotEmpty) ...[
          _label('اختر التركيز'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final st in _strengths)
                ChoiceChip(
                  label: Text('${st.strength} ${st.form}',
                      textDirection: TextDirection.ltr, style: _txt),
                  backgroundColor: Colors.white,
                  selectedColor: AppColors.primary.withOpacity(0.18),
                  checkmarkColor: AppColors.primary,
                  selected: _strength?.id == st.id,
                  onSelected: (_) {
                    _strength = st;
                    _commit();
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ── Badge ─────────────────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, {this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(10)),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.w700)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  تبويب التحاليل — وصلة بين الـ controller وواجهة PatientLabsTab
// ─────────────────────────────────────────────────────────────────────────────
class _LabsTabHost extends StatelessWidget {
  final PatientFileController ctrl;
  const _LabsTabHost({required this.ctrl});

  @override
  Widget build(BuildContext context) => Obx(() {
        final p = ctrl.patient.value;
        if (p == null) return const SizedBox.shrink();
        return PatientLabsTab(
          patient: p,
          recommended: ctrl.recommendedLabs.toList(),
          ranges: Map<String, LabRange?>.from(ctrl.labRanges),
          labTests: Map<String, LabTest>.from(ctrl.labTests),
          onAdd: ctrl.addLabResult,
          onRemove: ctrl.removeLabResult,
        );
      });
}
