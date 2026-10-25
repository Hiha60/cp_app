import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/iv_fluids.dart';
import '../../../core/services/alert_engine.dart';
import '../../../core/services/local_db_service.dart';
import '../../../data/models/patient_model.dart';
import '../../../data/models/org_models.dart';
import '../../../data/repositories/org_repository.dart';
import '../../../data/repositories/patient_repository.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../home/views/home_screen.dart' show HomeController;

class AddPatientController extends GetxController {
  // ── Form Keys ────────────────────────────────────────────────────────
  final formKeyBasic = GlobalKey<FormState>();
  final pageCtrl     = PageController();

  // ── Controllers ──────────────────────────────────────────────────────
  final nameCtrl       = TextEditingController();
  final ageCtrl        = TextEditingController();
  final monthsCtrl     = TextEditingController();
  final weightCtrl     = TextEditingController();
  final fileNumCtrl    = TextEditingController();

  // ── Focus (التنقل بين الحقول بـ Enter / Next) ───────────────────────
  final nameFocus      = FocusNode();
  final ageFocus       = FocusNode();
  final monthsFocus    = FocusNode();
  final weightFocus    = FocusNode();
  final fileNumFocus   = FocusNode();

  // ── State ────────────────────────────────────────────────────────────
  final currentStep        = 0.obs;
  final isLoading          = false.obs;
  final isSaving           = false.obs;

  // بيانات أساسية
  final selectedDate       = Rx<DateTime?>(null);
  final selectedDeptId     = ''.obs;
  /// أقسام المستشفى (لمدير المستشفى عند إضافة مريض)
  final hospitalDepts      = <DepartmentModel>[].obs;
  // الجنس 'M' | 'F' | null (اختياري) + الحمل — للنسب الطبيعية للتحاليل والتنبيهات
  final sex                = Rxn<String>();
  final isPregnant         = false.obs;
  // السن (سنين) كقيمة reactive (عشان خانة الحمل تتفتح/تتقفل حسب السن)
  final ageValue           = 0.obs;
  // الشهور (0–11) reactive — للعرض وقوائم الأمراض المزمنة فقط
  final monthsValue        = 0.obs;

  /// خانة الحمل تظهر فقط للأنثى من 13 لـ 55 سنة
  bool get canBePregnant =>
      sex.value == 'F' && ageValue.value >= 13 && ageValue.value <= 55;

  // ── الوزن التقديري للأطفال أقل من 12 سنة ─────────────────────────────
  final weightManual      = false.obs; // المستخدم كتب/عدّل الوزن بنفسه
  final weightEstimated   = false.obs; // الوزن الظاهر تقديري
  final canEstimateWeight = false.obs; // فيه وزن تقديري متاح للسن الحالي

  int get yearsValue => int.tryParse(ageCtrl.text.trim()) ?? 0;
  int get monthsPart =>
      (int.tryParse(monthsCtrl.text.trim()) ?? 0).clamp(0, 11).toInt();

  /// معادلات APLS: <سنة: 0.5×شهور+4 | 1–5: 2×سن+8 | 6–11: 3×سن+7
  static double? estimateWeightKg(int years, int months) {
    if (years >= 12) return null;
    final total = years * 12 + months;
    double w;
    if (total < 12) {
      w = total == 0 ? 3.5 : 0.5 * total + 4;
    } else {
      final y = total / 12.0;
      w = y < 6 ? 2 * y + 8 : 3 * y + 7;
    }
    return double.parse(w.toStringAsFixed(1));
  }

  void onAgeChanged(String v) {
    ageValue.value = int.tryParse(v.trim()) ?? 0;
    if (!canBePregnant) isPregnant.value = false;
    syncDefaultWeight();
  }

  void onMonthsChanged(String v) {
    monthsValue.value = monthsPart;
    syncDefaultWeight();
  }

  /// بيتنادى لما المستخدم يكتب في خانة الوزن بنفسه
  void onWeightEdited(String v) {
    weightManual.value = true;
    weightEstimated.value = false;
  }

  void useEstimatedWeight() {
    weightManual.value = false;
    syncDefaultWeight();
  }

  void syncDefaultWeight() {
    final hasAge =
        ageCtrl.text.trim().isNotEmpty || monthsCtrl.text.trim().isNotEmpty;
    final w = hasAge ? estimateWeightKg(yearsValue, monthsPart) : null;
    canEstimateWeight.value = w != null;
    if (weightManual.value) return; // المستخدم غيّره → ما نلمسوش
    if (w == null) {
      if (weightEstimated.value) weightCtrl.clear();
      weightEstimated.value = false;
      return;
    }
    weightCtrl.text =
        w == w.roundToDouble() ? w.toStringAsFixed(0) : w.toStringAsFixed(1);
    weightEstimated.value = true;
  }

  void setSex(String? s) {
    sex.value = s;
    if (!canBePregnant) isPregnant.value = false;
  }

  // التشخيص النهائي
  final finalDiagnoses     = <String>[].obs;
  final finalDiagnosisIds   = <int>[].obs;
  final diagSearchResults  = <Map<String, dynamic>>[].obs;
  final diagSearchLoading  = false.obs;
  final comorbSearchResults = <Map<String, dynamic>>[].obs;
  final comorbSearchLoading = false.obs;

  // الأعراض
  final topSymptoms        = <String>[].obs;   // أشهر 20 عرض (chips)
  final selectedSymptoms   = <String>[].obs;
  final customSymptoms     = <String>[].obs;   // اتضافت يدوي خارج القاموس
  final symptomSuggestions = <String>[].obs;   // نتايج البحث
  final symptomHint        = ''.obs;           // رسالة تحقق تحت خانة الإضافة
  // تشخيصات المستخدم وافق يكمل بيها رغم عدم توافقها مع الأعراض الحالية
  final Set<int> _compatAcked = {};

  // الأسئلة الثلاثة
  final hasComorbidities   = false.obs;
  final selectedComorbidities = <String>[].obs;
  final hasChronicMeds     = false.obs;
  final chronicMeds        = <MedicationModel>[].obs;
  final hasAllergies       = false.obs;
  final allergies          = <AllergyModel>[].obs;
  // بحث مستقل عن دواء الحساسية (منفصل عن بحث الأدوية المزمنة/الموصوفة
  // عشان الاتنين ممكن يظهروا في نفس الخطوة مع بعض)
  final allergyDrugResults = <DrugSearchResult>[].obs;
  final hasHerbs           = false.obs;
  final selectedHerbs      = <String>[].obs;
  final allHerbs           = <String>[].obs; // القايمة الثابتة (22 عشب) من القاعدة

  // الأدوية الموصوفة
  final prescribedMeds     = <MedicationModel>[].obs;

  // ── المحاليل الوريدية ──────────────────────────────────────────────
  final tookFluids         = false.obs;
  final fluidOrders        = <FluidOrder>[].obs;       // المحاليل المؤكدة
  final draftFluid         = Rx<FluidDef?>(null);      // المحلول قيد الإضافة
  final draftAdditives     = <FluidAdditive>[].obs;    // أمبولات/فيالات عليه
  // picker خاص بالأمبولات/الفيالات (منفصل عن picker الأدوية العادي)
  final fluidDrugResults   = <DrugSearchResult>[].obs;
  final fluidDrug          = Rx<DrugSearchResult?>(null);
  final fluidVariantLabels = <String>[].obs;
  final fluidSelectedLabel = ''.obs;
  final fluidSelected      = Rx<DrugSearchResult?>(null);
  final Map<String, DrugSearchResult> _fluidVariantByLabel = {};

  // Drug autocomplete
  final drugSearchResults  = <DrugSearchResult>[].obs;

  // الأصناف المتاحة لاسم البراند المختار — كل chip = التركيز + الشكل الصيدلي
  // مع بعض (مثال: "50 mg tab" / "250mg/5ml syrup")، بدون تكرار
  final drugStrengths      = <String>[].obs;
  final selectedStrengthLabel = ''.obs;

  final selectedDrug       = Rx<DrugSearchResult?>(null);
  // الصف النهائي المحدد بالكامل (تركيز + شكل صيدلي) — بيفضل null لحد ما
  // يتحدد الصنف بالكامل (تلقائي أو باختيار المستخدم)
  final selectedStrength   = Rx<DrugSearchResult?>(null);
  final selectedForm       = ''.obs;
  final selectedFrequency  = ''.obs;
  // عدد الأقراص/المل في الجرعة (اختياري)
  final selectedDoseQty    = Rxn<double>();

  // كل الأصناف الحقيقية (بدون cancelled) لنفس الاسم التجاري المختار +
  // خريطة: نص الـ chip ← الصف الكامل
  final Map<String, DrugSearchResult> _variantByLabel = {};

  @override
  void onInit() {
    super.onInit();
    _loadHerbs();
    _loadSymptoms();
    _loadDepartments();
    // معاينة التحاليل المطلوبة: بتتحدّث مع أي تغيير في التشخيصات/الأدوية
    ever(finalDiagnosisIds, (_) => _refreshLabPreview());
    ever(prescribedMeds, (_) => _refreshLabPreview());
    ever(chronicMeds, (_) => _refreshLabPreview());
    // اختصارات التشخيصات بتتربط بالقاعدة كل ما السن يتغيّر
    ever(ageValue, (_) => preloadShortcuts());
    ever(monthsValue, (_) => preloadShortcuts());
    preloadShortcuts();
  }

  // ── معاينة التحاليل المطلوبة (من التشخيصات + الأدوية) ──────────────────
  final previewLabs = <RecommendedLab>[].obs;
  int _labPreviewSeq = 0;

  Future<void> _refreshLabPreview() async {
    final seq = ++_labPreviewSeq;
    try {
      final meds = [...prescribedMeds, ...chronicMeds];
      final r = await LocalDbService.instance.getRecommendedLabsFor(
        diagnosisIds: finalDiagnosisIds.where((i) => i > 0).toList(),
        drugTokens: meds
            .map((m) =>
                MedTokens(label: m.brandName, genericTokens: m.genericTokens))
            .toList(),
      );
      if (seq == _labPreviewSeq) previewLabs.value = r;
    } catch (_) {
      if (seq == _labPreviewSeq) previewLabs.clear();
    }
  }

  Future<void> _loadDepartments() async {
    final u = AuthController.to.user;
    if (!u.isAdmin) return;
    try {
      hospitalDepts.value = await OrgRepository.instance.departments(u.hospitalId);
    } catch (_) {}
  }

  Future<void> _loadSymptoms() async {
    topSymptoms.value = await LocalDbService.instance.getTopSymptoms();
  }

  Future<void> _loadHerbs() async {
    allHerbs.value = await LocalDbService.instance.getAllHerbs();
  }

  void toggleHerb(String name) {
    if (selectedHerbs.contains(name)) {
      selectedHerbs.remove(name);
    } else {
      selectedHerbs.add(name);
    }
  }

  @override
  void onClose() {
    nameCtrl.dispose();
    ageCtrl.dispose();
    monthsCtrl.dispose();
    weightCtrl.dispose();
    fileNumCtrl.dispose();
    nameFocus.dispose();
    ageFocus.dispose();
    monthsFocus.dispose();
    weightFocus.dispose();
    fileNumFocus.dispose();
    pageCtrl.dispose();
    super.onClose();
  }

  // ── Navigation ───────────────────────────────────────────────────────
  Future<void> nextStep() async {
    if (currentStep.value == 0 && !formKeyBasic.currentState!.validate()) return;
    // قبل ما نسيب صفحة التشخيص: راجع توافق كل تشخيص مع الأعراض الحالية
    // (المستخدم ممكن يكون غيّر الأعراض بعد ما اختار التشخيص)
    if (currentStep.value == 1) {
      for (var i = 0; i < finalDiagnoses.length; i++) {
        if (!await _confirmCompat(finalDiagnosisIds[i], finalDiagnoses[i])) return;
      }
    }
    currentStep.value++;
    pageCtrl.animateToPage(
      currentStep.value,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void prevStep() {
    if (currentStep.value == 0) return;
    currentStep.value--;
    pageCtrl.animateToPage(
      currentStep.value,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ── Date Picker ─────────────────────────────────────────────────────
  Future<void> pickDate(BuildContext context) async {
    final now  = DateTime.now();
    final date = await showDatePicker(
      context:     context,
      initialDate: selectedDate.value ?? now,
      firstDate:   DateTime(now.year - 1),
      lastDate:    now,
      locale:      const Locale('ar'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF1565C0)),
        ),
        child: child!,
      ),
    );
    if (date != null) selectedDate.value = date;
  }

  // ── Age → comorbidities ─────────────────────────────────────────────
  // بنقرأ ageValue/monthsValue هنا عشان أي Obx بينادي الـ getter ده يتحدّث
  List<String> get ageComorbidities =>
      comorbiditiesForAge(ageValue.value, months: monthsValue.value);

  // ── اختصارات التشخيصات (مرتبة حسب السن) ─────────────────────────────
  List<DxShortcut> get comorbidityShortcuts =>
      comorbidityShortcutsForAge(ageValue.value, months: monthsValue.value);
  List<DxShortcut> get diagnosisShortcuts =>
      diagnosisShortcutsForAge(ageValue.value, months: monthsValue.value);

  /// term → (id, name) من جدول التشخيصات؛ null = مش موجود في القاعدة
  final Map<String, ({int id, String name})?> _shortcutCache = {};
  /// term → الاسم المربوط (reactive عشان حالة الاختيار تتحدّث)
  final resolvedShortcuts = <String, String>{}.obs;

  Future<({int id, String name})?> _resolveShortcut(DxShortcut s) async {
    if (_shortcutCache.containsKey(s.term)) return _shortcutCache[s.term];
    ({int id, String name})? found;
    try {
      final rows = await LocalDbService.instance.searchDiagnoses(s.term);
      if (rows.isNotEmpty) {
        final exact = rows.firstWhere(
            (r) => (r['name'] as String).toLowerCase() == s.term,
            orElse: () => rows.first);
        found = (id: exact['id'] as int, name: exact['name'] as String);
      }
    } catch (_) {/* القاعدة مش جاهزة → نرجع للـ label */}
    _shortcutCache[s.term] = found;
    if (found != null) resolvedShortcuts[s.term] = found.name;
    return found;
  }

  Future<void> preloadShortcuts() async {
    for (final s in [...comorbidityShortcuts, ...diagnosisShortcuts]) {
      await _resolveShortcut(s);
    }
  }

  bool isShortcutSelected(DxShortcut s, List<String> selected) {
    final n = resolvedShortcuts[s.term];
    return selected.contains(n ?? s.label);
  }

  Future<void> toggleComorbidityShortcut(DxShortcut s) async {
    final r = await _resolveShortcut(s);
    final name = r?.name ?? s.label;
    if (selectedComorbidities.contains(name)) {
      await removeComorbidity(name);
    } else {
      addComorbidity(name);
    }
  }

  Future<void> toggleDiagnosisShortcut(DxShortcut s) async {
    final r = await _resolveShortcut(s);
    if (r == null) {
      Get.snackbar('غير موجود', 'التشخيص "${s.label}" مش موجود في قاعدة البيانات',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    if (finalDiagnoses.contains(r.name)) {
      await removeDiagnosis(r.name);
    } else {
      await addFinalDiagnosis(r.id, r.name);
    }
  }

  // ── الأمراض المزمنة (نفس بحث التشخيصات) ──────────────────────────────
  void addComorbidity(String name) {
    if (!selectedComorbidities.contains(name)) selectedComorbidities.add(name);
    hasComorbidities.value = true;
  }

  Future<void> removeComorbidity(String name) async {
    selectedComorbidities.remove(name);
  }

  Future<void> removeDiagnosis(String name) async => removeFinalDiagnosis(name);

  Future<void> searchComorbidity(String q) async {
    if (q.trim().length < 2) { comorbSearchResults.clear(); return; }
    comorbSearchLoading.value = true;
    comorbSearchResults.value =
        _rankByAge(await LocalDbService.instance.searchDiagnoses(q));
    comorbSearchLoading.value = false;
  }

  /// نتايج البحث: التشخيصات المهمة للسن الأول، والباقي بترتيبه الأصلي
  List<Map<String, dynamic>> _rankByAge(List<Map<String, dynamic>> rows) {
    final prio = dxPriorityTermsForAge(ageValue.value, months: monthsValue.value);
    int rank(Map<String, dynamic> r) {
      final n = (r['name'] as String).toLowerCase();
      final i = prio.indexWhere(n.contains);
      return i == -1 ? 999 : i;
    }
    final idx = {for (var i = 0; i < rows.length; i++) rows[i]: i};
    final out = [...rows];
    out.sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : idx[a]!.compareTo(idx[b]!);
    });
    return out;
  }

  // ── Diagnosis Search ────────────────────────────────────────────────
  Future<void> searchDiagnosis(String q) async {
    if (q.trim().length < 2) { diagSearchResults.clear(); return; }
    diagSearchLoading.value = true;
    diagSearchResults.value =
        _rankByAge(await LocalDbService.instance.searchDiagnoses(q));
    diagSearchLoading.value = false;
  }

  Future<void> addFinalDiagnosis(int id, String name) async {
    if (finalDiagnoses.contains(name)) return;
    if (!await _confirmCompat(id, name)) return;
    finalDiagnoses.add(name);
    finalDiagnosisIds.add(id);
  }

  void removeFinalDiagnosis(String name) {
    final i = finalDiagnoses.indexOf(name);
    if (i == -1) return;
    finalDiagnoses.removeAt(i);
    finalDiagnosisIds.removeAt(i);
  }

  /// true = كمّل، false = المستخدم رفض الاستمرار
  Future<bool> _confirmCompat(int id, String name) async {
    if (_compatAcked.contains(id)) return true;
    final ok = await LocalDbService.instance.isDiagnosisCompatible(
      diagnosisId: id,
      symptoms: selectedSymptoms.toList(),
    );
    if (ok != false) return true; // متوافق، أو مش قادرين نحكم

    final go = await Get.dialog<bool>(AlertDialog(
      title: const Text('تنبيه',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
      content: Text(
        'هذه الأعراض ليست متوافقة مع التشخيص\n($name)\nهل تريد الاستمرار؟',
        style: const TextStyle(fontFamily: 'Cairo'),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false), child: const Text('لا')),
        ElevatedButton(
            onPressed: () => Get.back(result: true), child: const Text('نعم')),
      ],
    ));
    if (go == true) {
      _compatAcked.add(id);
      return true;
    }
    return false;
  }

  // ── Symptoms ─────────────────────────────────────────────────────────
  bool _hasSymptom(String name) =>
      selectedSymptoms.any((s) => s.toLowerCase() == name.toLowerCase());

  void toggleSymptom(String name, bool on) {
    if (on) {
      if (!_hasSymptom(name)) selectedSymptoms.add(name);
    } else {
      selectedSymptoms.removeWhere((s) => s.toLowerCase() == name.toLowerCase());
      customSymptoms.removeWhere((s) => s.toLowerCase() == name.toLowerCase());
    }
    // الأعراض اتغيرت → أي موافقة سابقة على "عدم التوافق" ما بقتش صالحة
    _compatAcked.clear();
  }

  Future<void> searchSymptom(String q) async {
    symptomHint.value = '';
    symptomSuggestions.value = await LocalDbService.instance.searchSymptoms(q);
  }

  /// إضافة عرض بالكتابة. بيرجع true لو اتضاف.
  ///  • موجود في القاموس → يتضاف على طول
  ///  • قريب من عرض موجود (غلطة إملائية محتملة) → "تقصد X؟" أو "أنا متأكد"
  ///  • مش موجود ومش قريب → تأكيد "أنا متأكد إنه عرض" ويتسجل كعرض يدوي
  Future<bool> addCustomSymptom(String raw) async {
    symptomHint.value = '';
    final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return false;
    if (!RegExp(r"^[A-Za-z][A-Za-z '\-]{1,39}$").hasMatch(text)) {
      symptomHint.value = 'اكتب العرض بالإنجليزية (حروف فقط)';
      return false;
    }

    final names = await LocalDbService.instance.allSymptomNames();
    final lower = text.toLowerCase();

    for (final n in names) {
      if (n.toLowerCase() == lower) {
        toggleSymptom(n, true);
        symptomSuggestions.clear();
        return true;
      }
    }

    // أقرب عرض في القاموس
    String? best;
    var bestDist = 999;
    for (final n in names) {
      final d = _levenshtein(lower, n.toLowerCase());
      if (d < bestDist) {
        bestDist = d;
        best = n;
      }
    }
    final threshold = lower.length <= 5 ? 1 : 2;

    if (best != null && bestDist <= threshold) {
      final choice = await Get.dialog<String>(AlertDialog(
        title: const Text('هل تقصد؟',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        content: Text('"$text" مش موجود في قاموس الأعراض.\nهل تقصد "$best"؟',
            style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: 'cancel'),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Get.back(result: 'force'),
              child: const Text('لا، أنا متأكد إنه عرض')),
          ElevatedButton(
              onPressed: () => Get.back(result: 'suggest'),
              child: Text('نعم، $best')),
        ],
      ));
      if (choice == 'suggest') {
        toggleSymptom(best, true);
        symptomSuggestions.clear();
        return true;
      }
      if (choice != 'force') return false;
    } else {
      final ok = await Get.dialog<bool>(AlertDialog(
        title: const Text('عرض غير موجود في القاموس',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        content: Text('"$text" مش موجود في قاموس الأعراض.\nهل أنت متأكد إنه عرض طبي صحيح؟',
            style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Get.back(result: true),
              child: const Text('أنا متأكد، أضفه')),
        ],
      ));
      if (ok != true) return false;
    }

    final normalized = text[0].toUpperCase() + text.substring(1).toLowerCase();
    toggleSymptom(normalized, true);
    if (!customSymptoms.contains(normalized)) customSymptoms.add(normalized);
    symptomSuggestions.clear();
    return true;
  }

  int _levenshtein(String a, String b) {
    final dp = List.generate(
        a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
    for (var i = 0; i <= a.length; i++) dp[i][0] = i;
    for (var j = 0; j <= b.length; j++) dp[0][j] = j;
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final c = a[i - 1] == b[j - 1] ? 0 : 1;
        final v = [dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + c];
        dp[i][j] = v.reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[a.length][b.length];
  }

  // ── Drug Autocomplete ────────────────────────────────────────────────
  Future<void> searchDrug(String q) async {
    if (q.trim().length < 2) { drugSearchResults.clear(); return; }
    drugSearchResults.value = await LocalDbService.instance.searchDrugs(q);
  }

  /// المستخدم اختار براند من نتائج البحث — نجيب كل أصنافه الحقيقية
  /// (بدون cancelled) ونحاول نحل التركيز والشكل تلقائيًا لأقصى درجة ممكنة.
  Future<void> selectDrug(DrugSearchResult drug) async {
    selectedDrug.value           = drug;
    selectedStrength.value       = null;
    selectedForm.value           = '';
    selectedFrequency.value      = '';
    selectedDoseQty.value        = null;
    selectedStrengthLabel.value  = '';
    drugStrengths.clear();
    _variantByLabel.clear();
    drugSearchResults.clear();

    final variants =
        await LocalDbService.instance.getStrengthsForBrand(drug.tradeName);

    // كل صنف = chip واحد "التركيز + الشكل". الأصناف المتكررة بنفس النص
    // (نفس التركيز ونفس الشكل) بتتدمج في chip واحد.
    for (final v in variants) {
      final label = _variantLabel(v);
      _variantByLabel.putIfAbsent(label, () => v);
    }

    if (_variantByLabel.length == 1) {
      // صنف واحد بس — اختاره تلقائي
      selectStrengthChoice(_variantByLabel.keys.first);
    } else {
      drugStrengths.value = _variantByLabel.keys.toList();
    }
  }

  /// المستخدم اختار chip (التركيز + الشكل) — ده آخر خطوة لتحديد الصنف
  void selectStrengthChoice(String label) {
    final row = _variantByLabel[label];
    if (row == null) return;
    selectedStrengthLabel.value = label;
    selectedDoseQty.value       = null; // الوحدة تتغير مع الصنف
    selectedStrength.value      = row;
    selectedForm.value          = row.form;
  }

  // اختصارات الأشكال الصيدلية كما هي في القاعدة → النص المعروض
  static const _formShort = <String, String>{
    'TABS': 'tab', 'F.C.TABS': 'f.c. tab', 'CAPS': 'cap',
    'SYRUP': 'syrup', 'SUSP': 'susp', 'SOLUTION': 'solution',
    'CREAM': 'cream', 'GEL': 'gel', 'OINT': 'oint', 'LOTION': 'lotion',
    'DROPS': 'drops', 'SPRAY': 'spray', 'VIAL': 'vial', 'AMP': 'amp',
    'INF': 'inf', 'INJ': 'inj', 'SUPP': 'supp', 'SACHET': 'sachet',
    'INHALER': 'inhaler', 'EYE': 'eye drops', 'EAR': 'ear drops',
    'NASAL': 'nasal', 'PATCH': 'patch', 'OVULES': 'ovule',
  };

  /// "50 mg tab" / "1% gel" / "250mg/5ml syrup"
  String _variantLabel(DrugSearchResult v) {
    final strength = v.strength.trim().toLowerCase();
    final formRaw  = v.form.trim();
    final form     = _formShort[formRaw.toUpperCase()] ?? formRaw.toLowerCase();
    final label    = [strength, form].where((e) => e.isNotEmpty).join(' ');
    return label.isEmpty ? v.tradeName : label;
  }

  void selectFrequency(String f) => selectedFrequency.value = f;

  /// الضغط على نفس القيمة تاني = إلغاء الاختيار
  void selectDoseQty(double q) =>
      selectedDoseQty.value = selectedDoseQty.value == q ? null : q;

  bool get canAddMed =>
      selectedDrug.value != null &&
      selectedStrength.value != null &&
      selectedFrequency.value.isNotEmpty;

  void addPrescribedMed() {
    if (!canAddMed) return;
    final s = selectedStrength.value!;
    prescribedMeds.add(MedicationModel(
      brandName:   s.brandName,
      genericName: s.genericName,
      rxcui:       s.rxcui,
      strength:    s.strength,
      form:        s.form,
      frequency:   selectedFrequency.value,
      normalizedGenerics: s.normalizedGenerics,
      doseQty:     selectedDoseQty.value,
    ));
    _resetDrugPicker();
  }

  void addChronicMed() {
    if (!canAddMed) return;
    final s = selectedStrength.value!;
    chronicMeds.add(MedicationModel(
      brandName:   s.brandName,
      genericName: s.genericName,
      rxcui:       s.rxcui,
      strength:    s.strength,
      form:        s.form,
      frequency:   selectedFrequency.value,
      normalizedGenerics: s.normalizedGenerics,
      isChronic:   true,
      doseQty:     selectedDoseQty.value,
    ));
    _resetDrugPicker();
  }

  void removePrescribedMed(int i) => prescribedMeds.removeAt(i);
  void removeChronicMed(int i)    => chronicMeds.removeAt(i);

  /// إلغاء اختيار الدواء الحالي بالكامل (زرار X في مربع البحث)
  void resetDrugSelection() => _resetDrugPicker();

  // ══════════════════════════════════════════════════════════════════════
  //  المحاليل الوريدية
  // ══════════════════════════════════════════════════════════════════════
  void startFluid(FluidDef f) {
    draftFluid.value = f;
    draftAdditives.clear();
    resetFluidPicker();
  }

  void cancelDraftFluid() {
    draftFluid.value = null;
    draftAdditives.clear();
    resetFluidPicker();
  }

  void resetFluidPicker() {
    fluidDrugResults.clear();
    fluidDrug.value = null;
    fluidSelected.value = null;
    fluidSelectedLabel.value = '';
    fluidVariantLabels.clear();
    _fluidVariantByLabel.clear();
  }

  /// بحث — أمبولات وفيالات فقط
  Future<void> searchFluidDrug(String q) async {
    if (q.trim().length < 2) { fluidDrugResults.clear(); return; }
    fluidDrugResults.value =
        await LocalDbService.instance.searchParenteralDrugs(q);
  }

  Future<void> selectFluidDrug(DrugSearchResult d) async {
    fluidDrug.value = d;
    fluidSelected.value = null;
    fluidSelectedLabel.value = '';
    fluidVariantLabels.clear();
    _fluidVariantByLabel.clear();
    fluidDrugResults.clear();

    final variants =
        await LocalDbService.instance.getParenteralVariants(d.tradeName);
    for (final v in variants) {
      _fluidVariantByLabel.putIfAbsent(_variantLabel(v), () => v);
    }
    if (_fluidVariantByLabel.length == 1) {
      selectFluidVariant(_fluidVariantByLabel.keys.first);
    } else {
      fluidVariantLabels.value = _fluidVariantByLabel.keys.toList();
    }
  }

  void selectFluidVariant(String label) {
    final row = _fluidVariantByLabel[label];
    if (row == null) return;
    fluidSelectedLabel.value = label;
    fluidSelected.value = row;
  }

  bool get canAddAdditive => fluidSelected.value != null;

  /// يضيف الأمبول/الفيال على المحلول؛ لو مش مناسب للوريد يسأل المستخدم
  /// (موافقة للاستكمال / رفض للإلغاء) ويحفظ التحذير عشان يظهر في التنبيهات.
  Future<void> addFluidAdditive() async {
    final s = fluidSelected.value;
    if (s == null) return;
    final warn = ivRouteWarning(
      brandName: s.brandName,
      genericName: s.genericName,
      tokens: s.genericTokens,
    );

    if (warn != null) {
      final ok = await Get.dialog<bool>(AlertDialog(
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Expanded(
                child: Text('تحذير: غير مناسب للحقن الوريدي',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ]),
            content: Text(
                '$warn\n\nهل تريد الاستكمال رغم ذلك؟ سيظهر التنبيه في خانة التنبيهات.',
                style: const TextStyle(fontFamily: 'Cairo')),
            actions: [
              TextButton(
                  onPressed: () => Get.back(result: false),
                  child: const Text('رفض (إلغاء)')),
              ElevatedButton(
                  onPressed: () => Get.back(result: true),
                  child: const Text('موافقة (استكمال)')),
            ],
          )) ??
          false;
      if (!ok) { resetFluidPicker(); return; }
    }

    final med = MedicationModel(
      brandName: s.brandName,
      genericName: s.genericName,
      rxcui: s.rxcui,
      strength: s.strength,
      form: s.form,
      frequency: 'مضاف على المحلول',
      normalizedGenerics: s.normalizedGenerics,
    );

    // عدم التوافق جوه الكيس (مثال: سيفترياكسون على رينجر فيه كالسيوم) —
    // بيتفحص مع المحلول ومع الأمبولات اللي اتضافت قبل كده على نفس الكيس.
    // مش بيتخزّن؛ التنبيه بيتحسب تاني في ملف المريض من البيانات المحفوظة.
    final bag = draftFluid.value;
    if (bag != null) {
      final newSnap = additiveSnapshot(med, 9000);
      final items = <({MedSnapshot fluid, MedSnapshot additive})>[
        (fluid: fluidSnapshot(bag), additive: newSnap),
        for (var i = 0; i < draftAdditives.length; i++)
          (
            fluid: additiveSnapshot(draftAdditives[i].med, 9001 + i),
            additive: newSnap
          ),
      ];
      final issues = (await AlertEngine.instance.checkAdditiveCompatibility(
        items,
        patient: PatientSnapshot(
          age: yearsValue,
          weightKg: double.tryParse(weightCtrl.text.trim()),
          diagnosisIds: const [],
          allergies: const [],
          comorbidities: const [],
        ),
      ))
          .where((a) => a.severity != AlertSeverity.minor && a.severity != AlertSeverity.info)
          .toList();
      if (issues.isNotEmpty) {
        final ok = await Get.dialog<bool>(AlertDialog(
              title: const Row(children: [
                Icon(Icons.science_rounded, color: Color(0xFFEF4444)),
                SizedBox(width: 8),
                Expanded(
                  child: Text('تحذير: عدم توافق داخل الكيس',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                ),
              ]),
              content: SingleChildScrollView(
                child: Text(
                    '${issues.map((a) => '${a.title}\n${a.body}').join('\n\n')}'
                    '\n\nهل تريد الاستكمال رغم ذلك؟',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
              ),
              actions: [
                TextButton(
                    onPressed: () => Get.back(result: false),
                    child: const Text('رفض (إلغاء)')),
                ElevatedButton(
                    onPressed: () => Get.back(result: true),
                    child: const Text('موافقة (استكمال)')),
              ],
            )) ??
            false;
        if (!ok) {
          resetFluidPicker();
          return;
        }
      }
    }

    draftAdditives.add(FluidAdditive(med: med, ivWarning: warn));
    resetFluidPicker();
  }

  void removeDraftAdditive(int i) => draftAdditives.removeAt(i);

  void confirmFluid() {
    final f = draftFluid.value;
    if (f == null) return;
    fluidOrders.add(FluidOrder(
        fluidId: f.id, name: f.name, additives: draftAdditives.toList()));
    cancelDraftFluid();
  }

  void removeFluid(int i) => fluidOrders.removeAt(i);

  void _resetDrugPicker() {
    selectedDrug.value           = null;
    selectedStrength.value       = null;
    selectedForm.value           = '';
    selectedFrequency.value      = '';
    selectedDoseQty.value        = null;
    selectedStrengthLabel.value  = '';
    drugStrengths.clear();
    _variantByLabel.clear();
  }

  // ── Allergy ──────────────────────────────────────────────────────────
  Future<void> searchAllergyDrug(String q) async {
    if (q.trim().length < 2) { allergyDrugResults.clear(); return; }
    allergyDrugResults.value = await LocalDbService.instance.searchDrugs(q);
  }

  /// [drugTokens] = المواد الفعالة الأصلية للدواء المختار (لعرض اسمه/عيلته)
  /// [scopeTokens] = التوكينز اللي فعليًا هتتحفظ كحساسية (نفس drugTokens لو
  /// النطاق "الدواء بس"، أو كل مواد العيلة لو النطاق "العيلة كاملة")
  void addAllergy({
    required String label,
    required String reactionType,
    required List<String> scopeTokens,
    String? className,
  }) {
    if (label.trim().isEmpty || scopeTokens.isEmpty) return;
    allergies.add(AllergyModel(
      drugName:       label.trim(),
      reactionType:   reactionType,
      allergenTokens: scopeTokens,
      className:      className,
    ));
    allergyDrugResults.clear();
  }

  void removeAllergy(int i) => allergies.removeAt(i);

  // ── Save ─────────────────────────────────────────────────────────────
  Future<void> save() async {
    isSaving.value = true;
    try {
      final auth = AuthController.to;
      final now  = DateTime.now();
      final admission = selectedDate.value ?? now;

      // قسم المريض: قسم الصيدلانى الحالى — ومدير المستشفى بيختاره بنفسه
      // (القواعد بتتحقق من الحالتين)
      final deptId = auth.user.isAdmin
          ? selectedDeptId.value
          : auth.user.departmentId;
      if (deptId == null || deptId.isEmpty) {
        isSaving.value = false;
        Get.snackbar(
            'تعذّر الحفظ',
            auth.user.isAdmin
                ? 'اختار قسم المريض الأول'
                : 'حسابك غير مرتبط بقسم. تواصل مع المدير');
        return;
      }

      // فحص التكرار
      final dup = await PatientRepository.instance.findDuplicate(
        hospitalId:    auth.user.hospitalId,
        departmentId:  deptId,
        fileNumber:    fileNumCtrl.text.trim(),
        admissionDate: admission,
      );

      if (dup != null) {
        isSaving.value = false;
        final go = await Get.dialog<bool>(_DuplicateDialog(
          addedBy: dup.addedByUserName,
        ));
        if (go == true) Get.toNamed('/patient/${dup.id}');
        return;
      }

      final patient = PatientModel(
        hospitalId:            auth.user.hospitalId,
        departmentId:          deptId,
        addedByUserId:         auth.user.id,
        addedByUserName:       auth.user.name,
        name:                  nameCtrl.text.trim(),
        age:                   yearsValue,
        ageMonths:             monthsPart,
        weightKg:              double.tryParse(weightCtrl.text.trim()),
        fileNumber:            fileNumCtrl.text.trim(),
        sex:                   sex.value,
        isPregnant:            canBePregnant && isPregnant.value,
        admissionDate:         admission,
        symptoms:              selectedSymptoms.toList(),
        customSymptoms:        customSymptoms.toList(),
        finalDiagnoses:        finalDiagnoses.toList(),
        finalDiagnosisIds:     finalDiagnosisIds.toList(),
        hasComorbidities:      hasComorbidities.value,
        comorbidities:         selectedComorbidities.toList(),
        hasChronicMedications: hasChronicMeds.value,
        chronicMedications:    chronicMeds.toList(),
        hasAllergies:          hasAllergies.value,
        allergies:             allergies.toList(),
        hasHerbs:              hasHerbs.value,
        herbs:                 selectedHerbs.map((n) => HerbModel(name: n)).toList(),
        prescribedMedications: prescribedMeds.toList(),
        fluids:                tookFluids.value ? fluidOrders.toList() : const [],
        createdAt:             now,
        updatedAt:             now,
      );

      final id = await PatientRepository.instance.addPatient(patient);

      // نفضّي الفورم، ونخلي Home على تاب المرضى، ونفتح الملف فوقه
      // (Get.toNamed بدل offNamed عشان زر الرجوع يرجّع للرئيسية)
      resetForm();
      if (Get.isRegistered<HomeController>()) {
        Get.find<HomeController>().go(1);
      }
      Get.toNamed('/patient/$id');
    } catch (e) {
      Get.snackbar('خطأ', 'فشل حفظ بيانات المريض: $e',
          backgroundColor: const Color(0xFFEF4444),
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isSaving.value = false;
    }
  }

  // ── Reset (بعد الحفظ) ───────────────────────────────────────────────
  void resetForm() {
    nameCtrl.clear();
    ageCtrl.clear();
    monthsCtrl.clear();
    weightCtrl.clear();
    fileNumCtrl.clear();
    selectedDate.value = null;
    selectedDeptId.value = '';
    sex.value = null;
    isPregnant.value = false;
    ageValue.value = 0;
    monthsValue.value = 0;
    weightManual.value = false;
    weightEstimated.value = false;
    canEstimateWeight.value = false;
    finalDiagnoses.clear();
    finalDiagnosisIds.clear();
    diagSearchResults.clear();
    comorbSearchResults.clear();
    selectedSymptoms.clear();
    customSymptoms.clear();
    symptomSuggestions.clear();
    symptomHint.value = '';
    _compatAcked.clear();
    hasComorbidities.value = false;
    selectedComorbidities.clear();
    hasChronicMeds.value = false;
    chronicMeds.clear();
    hasAllergies.value = false;
    allergies.clear();
    allergyDrugResults.clear();
    hasHerbs.value = false;
    selectedHerbs.clear();
    prescribedMeds.clear();
    tookFluids.value = false;
    fluidOrders.clear();
    cancelDraftFluid();
    drugSearchResults.clear();
    _resetDrugPicker();
    currentStep.value = 0;
    if (pageCtrl.hasClients) pageCtrl.jumpToPage(0);
  }

  // ── Validators ──────────────────────────────────────────────────────
  String? validateName(String? v)      => (v == null || v.trim().isEmpty) ? 'أدخل اسم المريض' : null;

  /// السن: سنين، أو شهور فقط (لو أقل من سنة) — لازم واحد منهم على الأقل
  String? validateAge(String? v) {
    final y = v?.trim() ?? '';
    if (y.isEmpty && monthsCtrl.text.trim().isEmpty) return 'أدخل السن';
    if (y.isNotEmpty) {
      final n = int.tryParse(y);
      if (n == null || n < 0 || n > 120) return 'سن غير صحيح';
    }
    return null;
  }

  String? validateMonths(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = int.tryParse(v.trim());
    if (n == null || n < 0 || n > 11) return '0–11';
    return null;
  }

  String? validateFileNum(String? v)   => (v == null || v.trim().isEmpty) ? 'أدخل رقم الملف' : null;
}

// ── Duplicate Dialog ─────────────────────────────────────────────────────────
class _DuplicateDialog extends StatelessWidget {
  final String addedBy;
  const _DuplicateDialog({required this.addedBy});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('المريض مسجّل مسبقاً', style: TextStyle(fontFamily:'Cairo', fontWeight:FontWeight.w700)),
    content: Text(
      'هذا المريض مسجّل بالفعل بواسطة $addedBy\nهل تريد فتح ملفه؟',
      style: const TextStyle(fontFamily:'Cairo'),
    ),
    actions: [
      TextButton(onPressed: () => Get.back(result: false), child: const Text('إلغاء')),
      ElevatedButton(onPressed: () => Get.back(result: true), child: const Text('فتح الملف')),
    ],
  );
}
