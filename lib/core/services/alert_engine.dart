import '../constants/app_constants.dart';
import 'local_db_service.dart';

// ── Helper: تحويل نص التركيز لرقم بالـ mg ──────────────────────────────────
// بيفهم "625mg", "1g", "1 GM", "500 mg", "200 mcg". بيرجع null لأي حاجة تانية
// (شراب mg/ml، فيال IU، إلخ) لأنها مش قابلة للتحويل المباشر بدون سياق الحجم.
// ⚠️ ما بيعرفش الشكل الصيدلي: "80 G" كريم هيتحوّل 80000 mg. لحساب الجرعة اليومية
// استخدم computeDailyDose (بيفحص الشكل الصيدلي) مش الدالة دي.
double? parseStrengthMg(String raw) {
  final s = raw.toLowerCase().trim();
  final match = RegExp(r'^([\d.]+)\s*(mg|gm|g|mcg|ug)$').firstMatch(s);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
  return switch (match.group(2)) {
    'g' || 'gm' => value * 1000,
    'mcg' || 'ug' => value / 1000,
    _ => value,
  };
}

/// يحوّل نص التكرار المخزّن مع الدواء لعدد مرات في اليوم (للـ Alert Engine).
/// بيفهم النصوص الجديدة والقديمة (للمرضى المسجلين قبل التحديث).
/// الجرعات الأقل من مرة يوميا (يوم بعد يوم / كل 3 أيام / أسبوع / شهر)
/// بترجع 1 عمداً: فحص الجرعة القصوى هيعتبرها مرة يوميا، فمش هيطلع تنبيه
/// جرعة زايدة غلط. PRN والنص غير المعروف بيرجعوا null.
int? parseFreqPerDay(String frequency) {
  const map = <String, int>{
    // الجديد
    'مرة يوميا': 1, 'مرتين يوميا': 2, '3 مرات يوميا': 3,
    '4 مرات يوميا': 4, '5 مرات يوميا': 5,
    'يوم بعد يوم': 1, 'مرة كل 3 أيام': 1, 'مرة كل أسبوع': 1, 'مرة كل شهر': 1,
    // القديم
    'od': 1, 'qd': 1, 'bd': 2, 'bid': 2, 'tid': 3, 'qid': 4,
    'كل 8 ساعات': 3, 'كل 12 ساعة': 2, 'كل 24 ساعة': 1, 'مرة واحدة': 1,
  };
  return map[frequency.trim().toLowerCase()];
}

/// متوسط عدد الجرعات في اليوم — كسري للجرعات الأقل من يومية (يوم بعد يوم = 0.5،
/// كل 3 أيام = 1/3، أسبوعي = 1/7، شهري = 1/30). parseFreqPerDay بترجع 1 للكل
/// (عمدًا)، وده كان هيطلّع تنبيه جرعة زايدة غلط لمكمل أسبوعي مثلًا؛ فالحساب
/// الجديد بيعتمد على نص التكرار. null = عند اللزوم / نص غير معروف.
double? parseDosesPerDay(String frequency) {
  const sub = <String, double>{
    'يوم بعد يوم': 0.5,
    'مرة كل 3 أيام': 1 / 3,
    'مرة كل أسبوع': 1 / 7,
    'مرة كل شهر': 1 / 30,
  };
  final f = frequency.trim().toLowerCase();
  return sub[f] ?? parseFreqPerDay(frequency)?.toDouble();
}

String _fmtNum(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  var s = v.toStringAsFixed(v.abs() < 1 ? 3 : 1);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return s;
}

// ── حساب الجرعة اليومية بالـ mg ───────────────────────────────────────────────
// بنحسب بس لما نكون واثقين من الرقم:
//  • شكل صيدلي واضح: صلب (أقراص/كبسولات/لبوس/أكياس) أو حقن (أمبولة/فيال) أو سائل
//    فموي (شراب/معلق/نقط) — الكريمات/الجل/القطرة/اللصقات... مستبعدة (تركيزها % أو
//    وزن العبوة مش جرعة).
//  • الشكل بيتاخد من dosage_form، ولو فاضي (بيحصل في القاعدة) من اسم الدواء
//    ("TAREG 160MG 14 F.C. TAB.").
//  • تركيز بالـ mg/g/mcg: "500 MG"، "1 G"، أو mg/ml ("250MG/5ML") للسوائل.
//  • السوائل لازم نعرف عدد المل في الجرعة (MedSnapshot.doseQty) وإلا نتخطى.
enum DoseForm { solid, parenteral, liquid, other }

final RegExp _reTopical = RegExp(
    r'\b(CREAM|GEL|OINT|OINTMENT|LOTION|SPRAY|SHAMPOO|EYE|EAR|OPHTH\w*|NASAL|'
    r'TOPICAL|PATCH|OVULES?|VAG\w*|INHAL\w*|IMPLANT|MOUTH\w*|PASTE|ENEMA|FOAM|'
    r'LOZENGES?|PENS?)\b',
    caseSensitive: false);
final RegExp _reParenteral = RegExp(
    r'\b(AMPS?|AMPOULES?|VIALS?|INJ|INJECTION|PFS)\b',
    caseSensitive: false);
final RegExp _reSolid = RegExp(
    r'\b(TABS?|TABLETS?|CAPS?|CAPSULES?|SUPPS?|SUPPOSITOR(Y|IES)|SACHETS?)\b',
    caseSensitive: false);
final RegExp _reLiquid = RegExp(
    r'\b(SYRUP|SUSP|SUSPENSION|SOLUTION|SOL|DROPS?|ELIXIR|LIQUID)\b',
    caseSensitive: false);

DoseForm _classifyFormText(String t) {
  if (t.trim().isEmpty) return DoseForm.other;
  if (_reTopical.hasMatch(t)) return DoseForm.other;
  if (_reParenteral.hasMatch(t)) return DoseForm.parenteral;
  if (_reSolid.hasMatch(t)) return DoseForm.solid;
  if (_reLiquid.hasMatch(t)) return DoseForm.liquid;
  return DoseForm.other;
}

DoseForm classifyDoseForm(String form, String brandName) =>
    form.trim().isNotEmpty
        ? _classifyFormText(form)
        : _classifyFormText(brandName);

// ── منتجات وريدية / محاليل ────────────────────────────────────────────────────
// ⚠️ classifyDoseForm مش بيعتبر 'INF' (محلول وريدي) شكل حقن، ولا بيفرّق بين
// "شكل مش معروف" و"موضعي صريح". الدوال دي مخصوصة لفحص التداخل/التكرار:
//   • isTopicalProduct = موضعي/عين/استنشاق... صريح فقط (المجهول يتعامل كجهازي).
//   • isIvProduct      = أمبولة/فيال/حقن/محلول تسريب.
final RegExp _reIv = RegExp(
    r'\b(INF|INFUSION|IV|I\.V\.?|AMPS?|AMPOULES?|VIALS?|INJ|INJECTION|PFS)\b',
    caseSensitive: false);
final RegExp _reInfusionFluid =
    RegExp(r'\b(INF|INFUSION)\b', caseSensitive: false);

String _formText(String form, String brand) =>
    form.trim().isNotEmpty ? form : brand;

bool isTopicalProduct(String form, String brandName) =>
    _reTopical.hasMatch(_formText(form, brandName));

bool isIvProduct(String form, String brandName) {
  final t = _formText(form, brandName);
  return _reIv.hasMatch(t) && !_reTopical.hasMatch(t);
}

/// محلول تسريب (كيس/زجاجة) — مش أمبولة/فيال.
bool isInfusionFluid(String form, String brandName) =>
    _reInfusionFluid.hasMatch(_formText(form, brandName)) &&
    !_reTopical.hasMatch(_formText(form, brandName));

/// مفاتيح "افتراضية" لمحتوى المنتج الوريدي — بتتضاف لمفاتيح التداخل عشان
/// قواعد زي سيفترياكسون × كالسيوم وريدي تشتغل على رينجر/هارتمان/أمبولة
/// كالسيوم، من غير ما تطلّع تنبيه لأقراص الكالسيوم الفموية.
///  iv:calcium       أي منتج وريدي فيه كالسيوم
///  iv:calcium_conc  كالسيوم مركّز (أمبولة جلوكونات/كلوريد) — مش محلول متوازن
///  iv:potassium     بوتاسيوم (من غير رينجر — تركيزه فسيولوجي)
///  iv:dextrose / iv:saline / iv:bicarbonate / iv:phosphate / iv:magnesium
Set<String> ivKeysFor(MedSnapshot m) {
  if (!isIvProduct(m.form, m.brandName)) return {};
  final t = m.genericTokens.map((e) => e.trim().toLowerCase()).toSet();
  const caNames = {
    'calcium',
    'calcium gluconate',
    'calcium chloride',
    'calcium levulinate',
    'calcium glubionate',
    'calcium lactate',
  };
  final keys = <String>{};
  final hasCa = t.any(caNames.contains);
  if (hasCa) {
    keys.add('iv:calcium');
    const balanced = {'sodium', 'potassium', 'glucose', 'dextrose', 'sodium lactate'};
    if (!t.any(balanced.contains)) keys.add('iv:calcium_conc');
  }
  if (!hasCa && (t.contains('potassium') || t.contains('potassium chloride'))) {
    keys.add('iv:potassium');
  }
  if (t.contains('glucose') || t.contains('dextrose')) keys.add('iv:dextrose');
  if (t.contains('sodium') || t.contains('sodium chloride')) {
    keys.add('iv:saline');
  }
  if (t.any((x) => x.contains('bicarbon'))) keys.add('iv:bicarbonate');
  if (t.any((x) => x.contains('phosphate'))) keys.add('iv:phosphate');
  if (t.any((x) => x.startsWith('magnesium'))) keys.add('iv:magnesium');
  return keys;
}

// ملف تعريفي لكل دواء (مفاتيح التداخل + العائلات + الجرعة) — بيتبني مرة واحدة
// في كل analyze ويتشارك بين فحص التداخلات وفحص التكرار.
class _Prof {
  final int idx;
  final MedSnapshot med;
  final bool topical, iv, fluid;
  final Set<String> keys; // مواد فعالة (+مرادفات) + class:* + iv:*
  final Set<String> canon; // كل المواد (موحّدة)
  final Set<String> activeCanon; // المواد الدوائية المعروفة فقط
  final List<FamilyMembership> fams; // بعد تطبيق route/sole/dose
  final Map<String, String> famIng; // family -> مادة (موحّدة)
  final double? dailyMg;
  const _Prof({
    required this.idx,
    required this.med,
    required this.topical,
    required this.iv,
    required this.fluid,
    required this.keys,
    required this.canon,
    required this.activeCanon,
    required this.fams,
    required this.famIng,
    required this.dailyMg,
  });
  String get label => med.brandName;

  /// دواء بمادة واحدة (الجرعة الرقمية بتتحسب بس لهذا النوع)
  bool get single => canon.length == 1 && !med.genericName.contains('+');
}

class _Cand {
  final String labelA, labelB, severity, type, effect;
  final String? mgmt, neonate, source;
  final bool verified, fromRule;
  const _Cand({
    required this.labelA,
    required this.labelB,
    required this.severity,
    required this.type,
    required this.effect,
    this.mgmt,
    this.neonate,
    this.source,
    this.verified = false,
    this.fromRule = false,
  });
  int get rank => switch (severity.toLowerCase()) {
        'major' => 0,
        'moderate' => 1,
        'minor' => 2,
        _ => 3,
      };
}

class DoseUnit {
  final double mgPerUnit; // mg في القرص/الأمبولة — أو mg في المل للسوائل
  final bool perMl;
  const DoseUnit(this.mgPerUnit, this.perMl);
}

DoseUnit? parseDoseUnit({
  required String strengthRaw,
  required String form,
  String brandName = '',
}) {
  final kind = classifyDoseForm(form, brandName);
  if (kind == DoseForm.other) return null;
  final s = strengthRaw.toUpperCase().replaceAll(RegExp(r'\s+'), '');

  double? toMg(String v, String u) {
    final x = double.tryParse(v);
    if (x == null) return null;
    return switch (u) {
      'MG' => x,
      'G' || 'GM' => x * 1000,
      'MCG' || 'UG' => x / 1000,
      _ => null,
    };
  }

  // "500MG" / "1G" — قرص/كبسولة/أمبولة. للسوائل مش معروف لكل كام مل → نتخطى.
  final plain = RegExp(r'^(\d+(?:\.\d+)?)(MG|GM|G|MCG|UG)$').firstMatch(s);
  if (plain != null) {
    if (kind == DoseForm.liquid) return null;
    final mg = toMg(plain.group(1)!, plain.group(2)!);
    if (mg == null || mg <= 0 || mg > 10000) return null;
    return DoseUnit(mg, false);
  }

  // "250MG/5ML" — سائل: تركيز/مل. حقن: محتوى الأمبولة/الفيال (20MG/2ML = 20 mg).
  final conc = RegExp(r'^(\d+(?:\.\d+)?)(MG|GM|G|MCG|UG)/(\d*(?:\.\d+)?)ML$')
      .firstMatch(s);
  if (conc != null) {
    final mg = toMg(conc.group(1)!, conc.group(2)!);
    final volStr = conc.group(3)!;
    final vol = volStr.isEmpty ? 1.0 : double.tryParse(volStr);
    if (mg == null || mg <= 0 || vol == null || vol <= 0) return null;
    if (kind == DoseForm.liquid) return DoseUnit(mg / vol, true);
    if (kind == DoseForm.parenteral && mg <= 10000) return DoseUnit(mg, false);
  }
  return null;
}

/// عدد المل/الأقراص اللي يتعرضوا كاختيارات في شاشة الإضافة.
class DoseQtyOptions {
  final List<double> values;
  final bool isMl; // true = مل (سائل) / false = عدد وحدات (قرص/أمبولة)
  const DoseQtyOptions(this.values, this.isMl);
}

String fmtQty(double v) => _fmtNum(v);

/// null = الدواء مش قابل للحساب الرقمي أصلاً (كريم، قطرة، تركيز مش mg...) → مفيش داعي نسأل.
DoseQtyOptions? doseQtyOptionsFor(
    {required String strength, required String form, String brandName = ''}) {
  final u =
      parseDoseUnit(strengthRaw: strength, form: form, brandName: brandName);
  if (u == null) return null;
  if (u.perMl) return const DoseQtyOptions([2.5, 5, 7.5, 10, 15], true);
  final kind = classifyDoseForm(form, brandName);
  if (kind == DoseForm.parenteral) return const DoseQtyOptions([1, 2], false);
  return const DoseQtyOptions([0.5, 1, 1.5, 2, 3, 4], false);
}

class DailyDose {
  final double mg;
  final bool assumedOneUnit; // doseQty مش مُدخل → افترضنا وحدة واحدة في الجرعة
  final String calc; // مثال: '500 mg × 1 × 3/يوم'
  const DailyDose(this.mg, this.assumedOneUnit, this.calc);
}

/// الجرعة اليومية (متوسط) بالـ mg، أو null لو مش قابلة للحساب بأمان.
DailyDose? computeDailyDose(MedSnapshot m) {
  final unit = parseDoseUnit(
      strengthRaw: m.strengthRaw, form: m.form, brandName: m.brandName);
  if (unit == null) return null;
  final perDay = parseDosesPerDay(m.frequency) ?? m.freqPerDay?.toDouble();
  if (perDay == null || perDay <= 0) return null;

  final given = (m.doseQty != null && m.doseQty! > 0) ? m.doseQty : null;
  if (unit.perMl && given == null) return null; // سائل: لازم عدد المل
  final qty = given ?? 1.0;

  final mg = unit.mgPerUnit * qty * perDay;
  final per = unit.perMl
      ? '${_fmtNum(unit.mgPerUnit)} mg/ml × ${_fmtNum(qty)} ml'
      : '${_fmtNum(unit.mgPerUnit)} mg × ${_fmtNum(qty)}';
  return DailyDose(mg, given == null, '$per × ${_fmtNum(perDay)}/يوم');
}

/// ينضّف ملاحظات generic_dose_limits للعرض: يشيل الروابط والـ ⚠️ ويقصّر.
String _cleanNotes(String? n, {int max = 240}) {
  if (n == null) return '';
  var t = n.trim();
  final i = t.indexOf(RegExp(r'(?:روابط|رابط):'));
  if (i > 0) t = t.substring(0, i).trim();
  t = t.replaceAll('⚠️', '').trim();
  if (t.length > max) t = '${t.substring(0, max).trim()}…';
  return t;
}

// ── نموذج التنبيه ─────────────────────────────────────────────────────────
enum AlertSeverity { major, moderate, minor, info }

class ClinicalAlert {
  final String typeCode; // مثال: '3.0', '2.1', '4.1'
  final String title;
  final String body;
  final AlertSeverity severity;
  final String? suggestion; // اقتراح تدخل
  final bool autoSuggestIntervention;

  // ── بيانات لتعبئة نموذج التدخل تلقائيًا ──
  final String? drugA; // الدواء الأول (اسم تجاري أو علمي)
  final String? drugB; // الدواء/العشب التاني (في التداخلات)
  final String? reason; // نص جاهز لحقل السبب/التوصية

  const ClinicalAlert({
    required this.typeCode,
    required this.title,
    required this.body,
    required this.severity,
    this.suggestion,
    this.autoSuggestIntervention = false,
    this.drugA,
    this.drugB,
    this.reason,
  });

  String get severityLabel => switch (severity) {
        AlertSeverity.major => 'Major',
        AlertSeverity.moderate => 'Moderate',
        AlertSeverity.minor => 'Minor',
        AlertSeverity.info => 'Info',
      };
}

// ── Medication snapshot لتمرير البيانات للـ engine ────────────────────────
class MedSnapshot {
  final int drugId;
  final String brandName;
  final String genericName;
  final int? rxcui; // ⚠️ دايمًا null حاليًا (شوف local_db_service.dart)
  final List<String>
      genericTokens; // أسماء المواد الفعالة lowercase — أساس كل المطابقة دلوقتي
  final double? strengthMg; // القيمة الرقمية للتركيز
  final String strengthRaw; // '625mg', '1g'...
  final String form;
  final String frequency; // 'BD', 'TID'...
  final int? freqPerDay; // 2, 3, 4...
  final bool isChronic; // دواء مزمن → يُستثنى من فحص 1.1

  /// عدد الوحدات في الجرعة الواحدة: أقراص/كبسولات/أمبولات — أو مل للسوائل.
  /// null = مش مُدخل: للأقراص/الحقن بنفترض وحدة واحدة، وللسوائل بنتخطى فحص الجرعة.
  final double? doseQty;

  const MedSnapshot({
    required this.drugId,
    required this.brandName,
    required this.genericName,
    this.rxcui,
    this.genericTokens = const [],
    this.strengthMg,
    required this.strengthRaw,
    required this.form,
    required this.frequency,
    this.freqPerDay,
    this.isChronic = false,
    this.doseQty,
  });
}

// ── Patient snapshot ─────────────────────────────────────────────────────
// معلومة حساسية واحدة عند المريض — label للعرض في التنبيه، وtokens أسماء
// المواد الفعالة (lowercase) اللي فعليًا هتتفحص. tokens فاضية = تسجيل قديم
// من قبل تحديث عائلات الأدوية (نص حر) وهيتفحص بالطريقة الاحتياطية القديمة.
class PatientAllergyInfo {
  final String label;
  final List<String> tokens;
  const PatientAllergyInfo({required this.label, required this.tokens});
}

// ── نتيجة تحليل للـ engine ───────────────────────────────────────────────────
class LabResultSnapshot {
  final String code, name, unit;
  final double? value; // رقمي
  final bool? abnormal; // نوعي
  final DateTime takenAt;
  const LabResultSnapshot({
    required this.code,
    required this.name,
    this.unit = '',
    this.value,
    this.abnormal,
    required this.takenAt,
  });
}

/// Cockcroft-Gault بالوزن الفعلي (mL/min). null لو الداتا ناقصة أو المريض <18
/// أو الجنس غير معروف. (للسمنة المفرطة/الأطفال يحتاج وزن معدّل/Schwartz.)
double? computeCrClCg({
  required int age,
  required double? weightKg,
  required String? sex,
  required double scr,
}) {
  if (age < 18 || weightKg == null || weightKg <= 0 || scr <= 0) return null;
  if (sex != 'M' && sex != 'F') return null;
  final v = ((140 - age) * weightKg) / (72 * scr);
  return sex == 'F' ? v * 0.85 : v;
}

class PatientSnapshot {
  final int age;
  final double? weightKg;
  final List<int> diagnosisIds;
  final List<String> diagnosisNames; // أسماء التشخيصات/الأعراض — للعرض في نص التنبيه
  final List<PatientAllergyInfo> allergies;
  final List<String> herbNames; // الأعشاب/المكملات اللي المريض بياخدها
  final List<String> comorbidities; // أسماء الأمراض المزمنة
  final bool hasCkd;
  final bool hasLiverDisease;
  final String? sex; // 'M' | 'F' | null (قديم/غير مسجّل)
  final bool isPregnant;
  final List<LabResultSnapshot> labs;

  /// آخر كرياتينين مسجّل → CrCl محسوب (Cockcroft-Gault)
  double? get crcl {
    LabResultSnapshot? scr;
    for (final l in labs) {
      if (l.code == 'creat' &&
          l.value != null &&
          (scr == null || l.takenAt.isAfter(scr.takenAt))) {
        scr = l;
      }
    }
    if (scr == null) return null;
    return computeCrClCg(
        age: age, weightKg: weightKg, sex: sex, scr: scr.value!);
  }

  /// قصور كلوي: مسجّل كمرض مزمن، أو CrCl المحسوب من التحاليل < 60
  bool get ckdEffective {
    final c = crcl;
    return hasCkd || (c != null && c < 60);
  }

  const PatientSnapshot({
    required this.age,
    this.weightKg,
    required this.diagnosisIds,
    this.diagnosisNames = const [],
    required this.allergies,
    this.herbNames = const [],
    required this.comorbidities,
    this.hasCkd = false,
    this.hasLiverDisease = false,
    this.sex,
    this.isPregnant = false,
    this.labs = const [],
  });
}

// ── هياكل داخلية لفحص حدود الجرعات ───────────────────────────────────────────
class _DoseEntry {
  final MedSnapshot med;
  final DoseLimitInfo info;
  final DailyDose dose;
  const _DoseEntry(this.med, this.info, this.dose);
}

class _LimitCalc {
  final double limitMg;
  final String basis; // مصدر الرقم: للبالغين / mg/kg × وزن / سقف البالغين...
  const _LimitCalc(this.limitMg, this.basis);
}

class _SourceLimit {
  final String name;
  final double limitMg;
  final String basis;
  final bool isPrimary;
  const _SourceLimit(this.name, this.limitMg, this.basis, this.isPrimary);
}

// ─────────────────────────────────────────────────────────────────────────────
//  ALERT ENGINE
// ─────────────────────────────────────────────────────────────────────────────
class AlertEngine {
  AlertEngine._();
  static final instance = AlertEngine._();

  final _db = LocalDbService.instance;

  /// الدالة الرئيسية — تمر على الترتيب: DDI/محاليل → Duplication → Herb → Allergy → Dose → Indication → Beers → LocalLearning
  ///
  /// [fluids]: المحاليل الوريدية لو بتتخزّن منفصلة عن [medications] — بتدخل في
  /// فحص التداخل والتكرار بس (مش في الجرعة/المؤشر). لو المحاليل أصلاً جوه
  /// [medications] سيب [fluids] فاضية.
  Future<List<ClinicalAlert>> analyze({
    required PatientSnapshot patient,
    required List<MedSnapshot> medications, // موصوفة + مزمنة
    List<MedSnapshot> fluids = const [],
    List<Map<String, dynamic>> localPatterns = const [],
  }) async {
    final alerts = <ClinicalAlert>[];
    final medTokens = medications
        .map((m) =>
            MedTokens(label: m.brandName, genericTokens: m.genericTokens))
        .toList();

    // ١. Drug-Drug Interactions + المحاليل كأدوية + تكرار علاجي
    final interactionMeds = [
      ...medications,
      ...fluids.where((f) => !medications
          .any((m) => m.drugId != 0 && m.drugId == f.drugId && m.brandName == f.brandName)),
    ];
    final profs = await _buildProfiles(interactionMeds);
    alerts.addAll(await _checkInteractions(interactionMeds, profs, patient));
    alerts.addAll(await _checkDuplication(profs, patient));

    // ٢. Herb-Drug Interactions (معطّلة فعليًا لحد ما نضيف تتبّع الأعشاب في بيانات المريض)
    alerts.addAll(await _checkHerb(medTokens, patient.herbNames));

    // ٣. Allergy Check
    alerts.addAll(await _checkAllergy(medications, patient));

    // ٤. Dose Check — (أ) حدود الجرعات على مستوى المادة الفعالة + الـ flags
    //    (مستقلة عن التشخيص)، (ب) الفحص القديم المرتبط بالتشخيص (كلوي/كبدي).
    final limits = await _checkDoseLimits(medications, patient);
    alerts.addAll(limits.alerts);
    alerts.addAll(await _checkDose(medications, patient, limits.numericAlerted));

    // ٥. Indication Check (1.1) — الأدوية الموصوفة فقط
    alerts.addAll(await _checkIndication(
        medications.where((m) => !m.isChronic).toList(), patient));

    // ٦. Beers Criteria (≥65 فقط)
    if (patient.age >= 65) {
      alerts.addAll(await _checkBeers(medTokens));
    }

    // ٦ب. نتائج التحاليل (حرجة/غير طبيعية/ناقصة)
    alerts.addAll(await _checkLabs(patient, medTokens));

    // ٧. Local Learning
    alerts.addAll(_checkLocalLearning(medications, localPatterns));

    return alerts;
  }

  // ── ملفات الأدوية (مفاتيح + عائلات) ──────────────────────────────────────────
  Future<List<_Prof>> _buildProfiles(List<MedSnapshot> meds) async {
    final out = <_Prof>[];
    for (var i = 0; i < meds.length; i++) {
      final m = meds[i];
      final topical = isTopicalProduct(m.form, m.brandName);
      final iv = isIvProduct(m.form, m.brandName);
      final fluid = isInfusionFluid(m.form, m.brandName);
      final info = await _db.tokenInfo(m.genericTokens);
      final canon = info.values.map((e) => e.canon).toSet();
      final active =
          info.values.where((e) => e.known).map((e) => e.canon).toSet();
      final dailyMg = computeDailyDose(m)?.mg;

      final fams = <FamilyMembership>[];
      final famIng = <String, String>{};
      final keys = <String>{};
      if (!topical) {
        keys.addAll(await _db.expandTokens(m.genericTokens));
        for (final f in await _db.getFamilyMemberships(m.genericTokens)) {
          if (f.routeScope == 'oral' && iv) continue;
          if (f.soleOnly && canon.length != 1) continue;
          if (f.doseGtMg != null && (dailyMg == null || dailyMg <= f.doseGtMg!)) {
            continue;
          }
          fams.add(f);
          keys.add('class:${f.family}');
          famIng.putIfAbsent(f.family,
              () => info[f.ingredient]?.canon ?? f.ingredient);
        }
        keys.addAll(ivKeysFor(m));
      }
      out.add(_Prof(
        idx: i,
        med: m,
        topical: topical,
        iv: iv,
        fluid: fluid,
        keys: keys,
        canon: canon,
        activeCanon: active,
        fams: fams,
        famIng: famIng,
        dailyMg: dailyMg,
      ));
    }
    return out;
  }

  // ── ١. Drug-Drug Interactions (الجدول القديم + قواعد v2 + المحاليل) ─────────
  // • الجدول القديم drug_interactions (OpenFDA + manual) كما هو.
  // • ddi_rules (DB 1.0.7): قواعد بمفاتيح مواد فعالة / عائلات / محتوى المحلول.
  // • نفس الزوج من الجدولين بيتدمج في تنبيه واحد بأعلى خطورة.
  Future<List<ClinicalAlert>> _checkInteractions(List<MedSnapshot> meds,
      List<_Prof> profs, PatientSnapshot patient) async {
    final cands = <_Cand>[];

    final medTokens = meds
        .map((m) => MedTokens(label: m.brandName, genericTokens: m.genericTokens))
        .toList();
    for (final r in await _db.checkDrugInteractions(medTokens)) {
      cands.add(_Cand(
        labelA: r.drugAName,
        labelB: r.drugBName,
        severity: r.severity,
        type: '3.0',
        effect: r.description,
      ));
    }

    final allKeys = profs.expand((p) => p.keys).toSet();
    final rules = await _db.getDdiRules(allKeys);
    final seen = <String>{};
    for (final r in rules) {
      final aList = profs.where((p) => p.keys.contains(r.aKey));
      final bList = profs.where((p) => p.keys.contains(r.bKey));
      for (final a in aList) {
        for (final b in bList) {
          if (a.idx == b.idx) continue;
          final lo = a.idx < b.idx ? a.idx : b.idx;
          final hi = a.idx < b.idx ? b.idx : a.idx;
          if (!seen.add('${r.id}|$lo|$hi')) continue;
          cands.add(_Cand(
            labelA: a.label,
            labelB: b.label,
            severity: r.severity,
            type: r.alertType,
            effect: r.effect,
            mgmt: r.management,
            neonate: r.neonateNote,
            source: r.source,
            verified: r.verified,
            fromRule: true,
          ));
        }
      }
    }
    return _candsToAlerts(cands, patient);
  }

  List<ClinicalAlert> _candsToAlerts(List<_Cand> cands, PatientSnapshot? patient) {
    final byPair = <String, List<_Cand>>{};
    for (final c in cands) {
      final a = c.labelA.toLowerCase(), b = c.labelB.toLowerCase();
      final key = a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
      byPair.putIfAbsent(key, () => []).add(c);
    }
    final alerts = <ClinicalAlert>[];
    for (final g in byPair.values) {
      g.sort((x, y) {
        final c = x.rank.compareTo(y.rank);
        if (c != 0) return c;
        return (y.fromRule ? 1 : 0).compareTo(x.fromRule ? 1 : 0);
      });
      final p = g.first;
      final is53 = p.type == '5.3';
      final lines = <String>[p.effect];
      if (patient != null && patient.age == 0 && p.neonate != null) {
        lines.add('👶 ${p.neonate}');
      }
      if (p.mgmt != null && p.mgmt!.isNotEmpty) {
        lines.add('الإجراء المقترح: ${p.mgmt}');
      }
      final extras = <String>[];
      for (final o in g.skip(1)) {
        final t = o.effect.trim();
        if (t.isEmpty || t == p.effect.trim() || extras.contains(t)) continue;
        extras.add(t);
        if (extras.length >= 3) break;
      }
      if (extras.isNotEmpty) {
        lines.add('تداخلات إضافية لنفس الزوج:');
        lines.addAll(extras.map((e) => '• $e'));
      }
      if (p.source != null) {
        lines.add('المصدر: ${p.source}${p.verified ? '' : ' (قيد المراجعة)'}');
      }
      final body = lines.join('\n');
      alerts.add(ClinicalAlert(
        typeCode: is53 ? '5.3' : '3.0',
        title: is53
            ? '🧪 عدم توافق/تداخل (محاليل وريدية): ${p.labelA} + ${p.labelB}'
            : '⚠️ تداخل دوائي: ${p.labelA} + ${p.labelB}',
        body: body,
        severity: _parseSeverity(p.severity),
        autoSuggestIntervention: true,
        drugA: p.labelA,
        drugB: p.labelB,
        reason: p.effect,
      ));
    }
    return alerts;
  }

  /// توافق مادة مضافة داخل كيس المحلول (نفس الكيس = أخطر تلامس): مثلاً فيال
  /// سيفترياكسون مضاف على رينجر. بيفحص قواعد الـ 5.3 بس (عدم التوافق الفيزيائي).
  Future<List<ClinicalAlert>> checkAdditiveCompatibility(
      List<({MedSnapshot fluid, MedSnapshot additive})> items,
      {PatientSnapshot? patient}) async {
    final out = <ClinicalAlert>[];
    for (final it in items) {
      final profs = await _buildProfiles([it.fluid, it.additive]);
      final rules = await _db.getDdiRules(profs.expand((p) => p.keys).toSet());
      final cands = <_Cand>[];
      for (final r in rules.where((r) => r.alertType == '5.3')) {
        final f = profs[0], a = profs[1];
        final hit = (f.keys.contains(r.aKey) && a.keys.contains(r.bKey)) ||
            (f.keys.contains(r.bKey) && a.keys.contains(r.aKey));
        if (!hit) continue;
        cands.add(_Cand(
          labelA: it.additive.brandName,
          labelB: it.fluid.brandName,
          severity: r.severity == 'Minor' ? 'Minor' : 'Major', // نفس الكيس
          type: '5.3',
          effect: r.effect,
          mgmt: r.management,
          neonate: r.neonateNote,
          source: r.source,
          verified: r.verified,
          fromRule: true,
        ));
      }
      for (final a in _candsToAlerts(cands, patient)) {
        out.add(ClinicalAlert(
          typeCode: '5.3',
          title: '🧪 عدم توافق داخل الكيس: ${it.additive.brandName} في ${it.fluid.brandName}',
          body: 'الإضافة دي على نفس المحلول غير مناسبة.\n${a.body}',
          severity: a.severity,
          autoSuggestIntervention: true,
          drugA: it.additive.brandName,
          drugB: it.fluid.brandName,
          reason: a.reason,
        ));
      }
    }
    return out;
  }

  // ── ٠. Therapeutic Duplication (1.2) ────────────────────────────────────────
  //  أ) نفس المادة الفعالة في أكتر من دواء (مع الجرعة الكلية مقابل الحد الأقصى)
  //  ب) نفس العائلة (مادتين مختلفتين) — الخطورة من drug_families.dup_severity
  //  ج) نفس المجموعة (info بس، لمجموعات group_dup=1)
  // ثوابت: المحاليل (INF) والإنسولين والمواد غير الدوائية (تجميلي/عشبي) مستثناة
  // من (أ)؛ الموضعي مستثنى من كله.
  String _medLine(_Prof p) {
    final bits = <String>[
      if (p.med.strengthRaw.trim().isNotEmpty) p.med.strengthRaw.trim(),
      if (p.med.frequency.trim().isNotEmpty) p.med.frequency.trim(),
    ];
    final tag = p.med.isChronic ? ' [مزمن]' : '';
    return '• ${p.label}$tag${bits.isEmpty ? '' : ' (${bits.join(' — ')})'}';
  }

  Future<List<ClinicalAlert>> _checkDuplication(
      List<_Prof> all, PatientSnapshot patient) async {
    final alerts = <ClinicalAlert>[];
    final covered = <String>{};
    String pk(int a, int b) => a < b ? '$a|$b' : '$b|$a';
    void coverAll(Iterable<int> idxs) {
      final l = idxs.toList();
      for (var i = 0; i < l.length; i++) {
        for (var j = i + 1; j < l.length; j++) {
          covered.add(pk(l[i], l[j]));
        }
      }
    }

    final profs = all.where((p) => !p.topical).toList();

    // ── أ) نفس المادة الفعالة ──
    final byIng = <String, List<_Prof>>{};
    for (final p in profs) {
      if (p.fluid) continue;
      if (p.fams.any((f) => f.family == 'insulin')) continue;
      for (final c in p.activeCanon) {
        byIng.putIfAbsent(c, () => []).add(p);
      }
    }
    // دمج المواد اللي ليها نفس مجموعة الأدوية في تنبيه واحد
    final merged = <String, ({Set<int> idxs, List<String> ings, List<_Prof> meds})>{};
    byIng.forEach((ing, list) {
      final idxs = list.map((p) => p.idx).toSet();
      if (idxs.length < 2) return;
      final key = (idxs.toList()..sort()).join(',');
      final cur = merged[key];
      if (cur == null) {
        merged[key] = (idxs: idxs, ings: [ing], meds: list);
      } else {
        cur.ings.add(ing);
      }
    });
    for (final g in merged.values) {
      final lines = <String>[];
      var exceeded = false, isUl = false;
      for (final ing in g.ings) {
        final r = await _dupDoseLines(ing, g.meds, patient);
        lines.addAll(r.lines);
        exceeded = exceeded || r.exceeded;
        isUl = isUl || r.ul;
      }
      final ings = g.ings.join('، ');
      final sev = exceeded
          ? AlertSeverity.major
          : isUl
              ? AlertSeverity.info
              : AlertSeverity.moderate;
      final labels = g.meds.map((p) => p.label).toSet().toList();
      alerts.add(ClinicalAlert(
        typeCode: '1.2',
        title: '🔁 تكرار نفس المادة الفعالة ($ings): ${labels.join(' + ')}',
        body: [
          'أكتر من دواء فيهم نفس المادة الفعالة:',
          ...g.meds.map(_medLine),
          ...lines,
          if (!exceeded)
            'راجع الحاجة لأكتر من صنف؛ لو مقصود (مثلاً وريدي + فموي) تأكد إن الجرعة الكلية آمنة.',
        ].join('\n'),
        severity: sev,
        autoSuggestIntervention: !isUl,
        drugA: labels.first,
        drugB: labels.length > 1 ? labels[1] : null,
        reason: 'تكرار نفس المادة الفعالة ($ings) في ${labels.join(' و ')}'
            '${exceeded ? ' مع تجاوز الجرعة القصوى' : ''}',
      ));
      coverAll(g.idxs);
    }

    // ── ب) نفس العائلة ──
    final famMembers = <String, List<_Prof>>{};
    final famMeta = <String, FamilyMembership>{};
    for (final p in profs) {
      for (final f in p.fams) {
        famMembers.putIfAbsent(f.family, () => []);
        if (!famMembers[f.family]!.contains(p)) famMembers[f.family]!.add(p);
        famMeta.putIfAbsent(f.family, () => f);
      }
    }
    final famOrder = famMembers.keys.toList()
      ..sort((a, b) {
        final c = (famMeta[a]!.isBroad ? 1 : 0).compareTo(famMeta[b]!.isBroad ? 1 : 0);
        return c != 0 ? c : a.compareTo(b);
      });
    for (final fk in famOrder) {
      final meta = famMeta[fk]!;
      if (meta.dupSeverity == 'none') continue;
      final members = famMembers[fk]!;
      if (members.length < 2) continue;
      final involved = <_Prof>{};
      final pairs = <String>[];
      for (var i = 0; i < members.length; i++) {
        for (var j = i + 1; j < members.length; j++) {
          final a = members[i], b = members[j];
          if (a.famIng[fk] == b.famIng[fk]) continue; // نفس المادة = تنبيه (أ)
          if (covered.contains(pk(a.idx, b.idx))) continue;
          involved..add(a)..add(b);
          pairs.add(pk(a.idx, b.idx));
        }
      }
      if (involved.isEmpty) continue;
      covered.addAll(pairs);
      final list = involved.toList()..sort((x, y) => x.idx.compareTo(y.idx));
      final labels = list.map((p) => p.label).toList();
      final note = meta.dupNote;
      alerts.add(ClinicalAlert(
        typeCode: '1.2',
        title: '🔁 تكرار علاجي — نفس العائلة (${meta.familyAr}): ${labels.join(' + ')}',
        body: [
          'الأدوية دي من نفس العائلة (${meta.familyAr}):',
          ...list.map((p) => '${_medLine(p)} — ${p.famIng[fk]}'),
          if (note != null && note.isNotEmpty) note,
          'الجمع بين دوائين من نفس العائلة غالبًا بيزوّد الأعراض الجانبية من غير فايدة إضافية — راجع الضرورة.',
        ].join('\n'),
        severity: _parseSeverity(meta.dupSeverity),
        autoSuggestIntervention: true,
        drugA: labels.first,
        drugB: labels[1],
        reason: 'تكرار علاجي: ${labels.join(' و ')} من نفس العائلة (${meta.familyAr})',
      ));
    }

    // ── ج) نفس المجموعة (info) ──
    final grpMembers = <String, List<_Prof>>{};
    final grpName = <String, String>{};
    for (final p in profs) {
      for (final f in p.fams.where((f) => f.groupDup)) {
        grpMembers.putIfAbsent(f.group, () => []);
        if (!grpMembers[f.group]!.contains(p)) grpMembers[f.group]!.add(p);
        grpName[f.group] = f.groupAr;
      }
    }
    for (final e in grpMembers.entries) {
      final members = e.value;
      final involved = <_Prof>{};
      final pairs = <String>[];
      for (var i = 0; i < members.length; i++) {
        for (var j = i + 1; j < members.length; j++) {
          final a = members[i], b = members[j];
          if (covered.contains(pk(a.idx, b.idx))) continue;
          involved..add(a)..add(b);
          pairs.add(pk(a.idx, b.idx));
        }
      }
      if (involved.isEmpty) continue;
      covered.addAll(pairs);
      final list = involved.toList()..sort((x, y) => x.idx.compareTo(y.idx));
      final labels = list.map((p) => p.label).toList();
      alerts.add(ClinicalAlert(
        typeCode: '1.2',
        title: 'ℹ️ أدوية من نفس المجموعة (${grpName[e.key]}): ${labels.join(' + ')}',
        body: [
          'أكتر من دواء من مجموعة (${grpName[e.key]}):',
          ...list.map(_medLine),
          'تأكد إن الجمع مقصود ومبرّر.',
        ].join('\n'),
        severity: AlertSeverity.info,
        drugA: labels.first,
        drugB: labels[1],
      ));
    }
    return alerts;
  }

  /// سطور الجرعة الكلية لمادة مكررة + مقارنتها بالحد الأقصى (generic_dose_limits).
  Future<({List<String> lines, bool exceeded, bool ul})> _dupDoseLines(
      String ing, List<_Prof> group, PatientSnapshot patient) async {
    final singles = group.where((p) => p.single && p.dailyMg != null).toList();
    final skipped = group.where((p) => !(p.single && p.dailyMg != null)).toList();
    if (singles.isEmpty) {
      return (
        lines: [
          'الجرعة الكلية لـ $ing غير قابلة للحساب (تركيبة مركبة أو شكل/تكرار/كمية غير معروفة).'
        ],
        exceeded: false,
        ul: false
      );
    }
    final total = singles.fold<double>(0, (s, p) => s + p.dailyMg!);
    final lines = <String>[
      'الجرعة اليومية الكلية من $ing: ${_fmtNum(total)} mg '
          '(${singles.map((p) => '${p.label}: ${_fmtNum(p.dailyMg!)}').join(' + ')})',
    ];
    var exceeded = false, ul = false;
    final info = await _db.getDoseLimits(singles.first.med.genericTokens);
    if (info != null) {
      ul = info.hasUl;
      final sources = _sourceLimits(info, patient);
      if (sources.isNotEmpty) {
        final primary = sources.firstWhere((s) => s.isPrimary, orElse: () => sources.first);
        final pct = (total / primary.limitMg * 100).round();
        exceeded = sources.any((s) => total > s.limitMg + 1e-9);
        lines.add('${ul ? 'الحد الأعلى الآمن (UL)' : 'الحد الأقصى اليومي'}: '
            '${_fmtNum(primary.limitMg)} mg ($pct% منه) — ${primary.basis}'
            '${exceeded ? ' ← تجاوز' : ''}');
      } else {
        lines.add('مفيش حد أقصى مسجّل يتناسب مع سن/وزن المريض للمقارنة.');
      }
    } else {
      lines.add('مفيش حد أقصى مسجّل لـ $ing في القاعدة للمقارنة.');
    }
    if (skipped.isNotEmpty) {
      lines.add('(لم تُحسب في الإجمالي: ${skipped.map((p) => p.label).join('، ')} — '
          'تركيبة مركبة أو جرعة غير قابلة للحساب)');
    }
    return (lines: lines, exceeded: exceeded, ul: ul);
  }

  // ── ٢. Herb-Drug Interactions ─────────────────────────────────────
  Future<List<ClinicalAlert>> _checkHerb(
      List<MedTokens> medTokens, List<String> herbNames) async {
    final results =
        await _db.checkHerbInteractions(medTokens, herbNames: herbNames);
    return results
        .map((r) => ClinicalAlert(
              typeCode: '3.0',
              title: '🌿 تداخل عشبي: ${r.herbName} + ${r.drugName}',
              body: r.description,
              severity: _parseSeverity(r.severity),
              autoSuggestIntervention: true,
              drugA: r.drugName,
              drugB: r.herbName,
              reason: r.description,
            ))
        .toList();
  }

  // ── ٣. Allergy Check (2.1) ────────────────────────────────────────
  Future<List<ClinicalAlert>> _checkAllergy(
      List<MedSnapshot> meds, PatientSnapshot patient) async {
    if (patient.allergies.isEmpty) return [];
    final alerts = <ClinicalAlert>[];

    for (final med in meds) {
      if (med.genericTokens.isEmpty) continue;
      for (final allergy in patient.allergies) {
        bool matched;
        if (allergy.tokens.isNotEmpty) {
          // تسجيل جديد: مطابقة مباشرة ودقيقة بالتوكينز اللي الصيدلي اختارها
          matched = med.genericTokens.any(allergy.tokens.contains);
        } else {
          // تسجيل قديم (نص حر) — رجوع للمطابقة الاحتياطية القديمة
          matched = await _db.checkAllergy(
            genericTokens: med.genericTokens,
            fallbackText: '${med.brandName} ${med.genericName}',
            allergenNames: [allergy.label],
          );
        }
        if (matched) {
          alerts.add(ClinicalAlert(
            typeCode: '2.1',
            title: '🚫 تنبيه حساسية: ${med.brandName}',
            body:
                '${med.genericName} — خطر حساسية لدى المريض (${allergy.label})',
            severity: AlertSeverity.major,
            autoSuggestIntervention: true,
            drugA: med.brandName,
          ));
          break; // كفاية تنبيه واحد لكل دواء
        }
      }
    }
    return alerts;
  }

  // ── ٤-ب. Dose Check المرتبط بالتشخيص (4.1) ─────────────────────────
  // ملحوظة: بيشتغل بس لو patient.diagnosisIds مليانة (resolveDiagnosisIds في
  // patient_file_screen.dart). بيفضل مفيد للتعديل الكلوي/الكبدي والسقف الخاص
  // بالتشخيص. [numericAlerted] = الأدوية اللي _checkDoseLimits طلّع ليها تنبيه
  // تجاوز جرعة بالفعل، فبنتخطى فحص الحد الأقصى هنا عشان ما يتكررش.
  Future<List<ClinicalAlert>> _checkDose(List<MedSnapshot> meds,
      PatientSnapshot patient, Set<int> numericAlerted) async {
    final alerts = <ClinicalAlert>[];

    for (final med in meds) {
      if (med.genericTokens.isEmpty) continue;

      final dose = await _db.getDoseInfo(
        genericTokens: med.genericTokens,
        diagnosisIds: patient.diagnosisIds,
      );
      if (dose == null) continue;

      // renal/hepatic warning — ما بيحتاجش strengthMg
      if (dose.renalAdjustment != null && patient.ckdEffective) {
        alerts.add(ClinicalAlert(
          typeCode: '4.1',
          title: '⚠️ تعديل جرعة كلوي: ${med.brandName}',
          body: dose.renalAdjustment!,
          severity: AlertSeverity.major,
          autoSuggestIntervention: true,
          drugA: med.brandName,
          reason: 'فشل كلوي — ${dose.renalAdjustment!}',
        ));
      }
      if (dose.hepaticAdjustment != null && patient.hasLiverDisease) {
        alerts.add(ClinicalAlert(
          typeCode: '4.1',
          title: '⚠️ تعديل جرعة كبدي: ${med.brandName}',
          body: dose.hepaticAdjustment!,
          severity: AlertSeverity.major,
          autoSuggestIntervention: true,
          drugA: med.brandName,
          reason: 'فشل كبدي — ${dose.hepaticAdjustment!}',
        ));
      }

      // فحص تجاوز الحد الأقصى — بنحسبه بس لما نكون واثقين من الرقم:
      //  • مادة واحدة (الدواء المركّب التركيز بتاعه مش بيخص مادة بعينها)
      //  • شكل صيدلي وتركيز واضحين (computeDailyDose) — مش كريم/شراب بدون حجم
      //  • تكرار معروف (PRN أو نص غير معروف → نتخطى بدل ما نفترض مرة يوميًا)
      if (med.genericName.contains('+')) continue;
      if (numericAlerted.contains(med.drugId)) continue;
      if ((dose.adultUnit ?? 'mg') != 'mg') continue;
      final daily = computeDailyDose(med);
      if (daily == null) continue;
      final dailyDose = daily.mg;

      // dose range check
      final maxMg = _maxDailyForPatient(dose, patient);
      if (maxMg != null && dailyDose > maxMg) {
        alerts.add(ClinicalAlert(
          typeCode: '4.1',
          title: '⚠️ جرعة تتجاوز الموصى به: ${med.brandName}',
          body: 'الجرعة اليومية الحالية: ${_fmtNum(dailyDose)} mg (${daily.calc})'
              '${daily.assumedOneUnit ? '\n(على افتراض وحدة واحدة في كل جرعة)' : ''}\n'
              'الحد الأقصى الموصى به: ${_fmtNum(maxMg)} mg',
          severity: AlertSeverity.major,
          autoSuggestIntervention: true,
          drugA: med.brandName,
          reason:
              'تجاوز الحد الأقصى اليومي (${maxMg.toStringAsFixed(0)} mg)',
        ));
      }
    }
    return alerts;
  }

  // ── ٤-أ. حدود الجرعات (generic_dose_limits) + الـ flags ─────────────────────
  // • مستقل عن التشخيص: بيشتغل على أي دواء ليه صف في generic_dose_limits.
  // • الجرعة بتتجمّع لو نفس المادة في أكتر من دواء (موصوف + مزمن مثلًا).
  // • السقف حسب فئة المريض: بالغ ← adult_max_daily_mg | طفل ← الأقل من
  //   (mg/kg × الوزن) وسقف البالغين. كل مصدر بديل (generic_dose_limit_alt) بيتقارن
  //   لوحده، وبيتعرض في التنبيه بالمصدر.
  // • الـ flags بتتقارن بحالة المريض (العمر، تكرار الدواء، مزمن/موصوف، كلى/كبد).
  // الدواء المركّب (genericName فيه '+') بيتفحص بالـ flags بس — مش بالسقف الرقمي.
  Future<({List<ClinicalAlert> alerts, Set<int> numericAlerted})>
      _checkDoseLimits(List<MedSnapshot> meds, PatientSnapshot patient) async {
    final alerts = <ClinicalAlert>[];
    final numericAlerted = <int>{};
    final entries = <_DoseEntry>[];

    for (final med in meds) {
      if (med.genericTokens.isEmpty) continue;
      final info = await _db.getDoseLimits(med.genericTokens);
      if (info == null) continue;

      alerts.addAll(_flagAlerts(med, info, patient));

      if (med.genericName.contains('+')) continue;
      // سقف الـ UL للمكملات خاص بالفم — الحقن (مثلاً حديد وريدي) مايتقارنش بيه
      if (info.hasUl &&
          classifyDoseForm(med.form, med.brandName) == DoseForm.parenteral) {
        continue;
      }
      final dose = computeDailyDose(med);
      if (dose == null) continue;
      entries.add(_DoseEntry(med, info, dose));
    }

    // تجميع حسب المادة الفعالة
    final groups = <String, List<_DoseEntry>>{};
    for (final e in entries) {
      groups.putIfAbsent(e.info.key, () => []).add(e);
    }

    for (final g in groups.values) {
      final info = g.first.info;
      final total = g.fold<double>(0, (sum, e) => sum + e.dose.mg);
      final sources = _sourceLimits(info, patient);
      if (sources.isEmpty) continue;

      bool over(_SourceLimit s) => total > s.limitMg + 1e-9;
      final exceeded = sources.where(over).toList();
      if (exceeded.isEmpty) continue;

      final primaryOver = exceeded.any((s) => s.isPrimary);
      final isUl = info.hasUl;
      final brands = g.map((e) => e.med.brandName).toSet().join(' + ');

      final lines = <String>[];
      if (g.length == 1) {
        lines.add(
            'الجرعة اليومية المحسوبة: ${_fmtNum(total)} mg (${g.first.dose.calc})');
      } else {
        lines.add('الجرعة اليومية التراكمية (نفس المادة في ${g.length} أدوية): '
            '${_fmtNum(total)} mg');
        for (final e in g) {
          lines.add(
              '  • ${e.med.brandName}: ${_fmtNum(e.dose.mg)} mg (${e.dose.calc})');
        }
      }
      if (g.any((e) => e.dose.assumedOneUnit)) {
        lines.add('(الحساب على افتراض وحدة واحدة — قرص/كبسولة/أمبولة — في كل جرعة)');
      }
      lines.add(isUl
          ? 'الحد الأعلى الآمن (UL) للمكمل — مش بالضرورة خطأ لو جرعة علاجية:'
          : 'الحد الأقصى اليومي حسب المصدر:');
      for (final s in sources) {
        lines.add('• ${s.name}${s.isPrimary ? ' (الأساسي)' : ''}: '
            '${_fmtNum(s.limitMg)} mg/يوم — ${s.basis}${over(s) ? ' ← تجاوز' : ''}');
      }
      if (info.hasFlag('indication_dependent')) {
        lines.add('ملحوظة: ده السقف المطلق — بعض الدواعي سقفها أقل.');
      }
      if (patient.age < 18 && info.hasFlag('age_band_not_linear')) {
        lines.add(
            'ملحوظة: جرعات الأطفال لهذا الدواء بشرائح عمرية/وزنية ثابتة (مش بالكيلو) — راجع الملاحظات.');
      }
      final notes = _cleanNotes(info.primary.notes);
      if (notes.isNotEmpty) lines.add('ملاحظات: $notes');
      if (!info.primary.verified) {
        lines.add('⚠️ الرقم محل خلاف بين المصادر أو غير مؤكد — راجع المصادر.');
      }

      final first = exceeded.first;
      alerts.add(ClinicalAlert(
        typeCode: '4.1',
        title: !primaryOver
            ? '⚠️ جرعة فوق سقف أحد المصادر: $brands'
            : isUl
                ? '⚠️ تجاوز الحد الأعلى الآمن (UL): $brands'
                : '⚠️ جرعة تتجاوز الحد الأقصى: $brands',
        body: lines.join('\n'),
        // UL = حد مكمل غذائي، مش سقف علاجي (حمض فوليك 5mg جرعة علاجية شائعة)
        // فبيطلع info بس. تجاوز سقف مصدر بديل فقط = moderate.
        severity: isUl
            ? AlertSeverity.info
            : (primaryOver ? AlertSeverity.major : AlertSeverity.moderate),
        autoSuggestIntervention: !isUl,
        drugA: brands,
        reason: 'تجاوز الحد الأقصى اليومي: ${_fmtNum(total)} mg مقابل '
            '${_fmtNum(first.limitMg)} mg (${first.name})',
      ));
      numericAlerted.addAll(g.map((e) => e.med.drugId));
    }

    // طفل ووزنه مش مُدخل → مش قادرين نفحص السقف بالكيلو
    final hasWeight = (patient.weightKg ?? 0) > 0;
    if (patient.age < 18 && !hasWeight) {
      final needWeight = entries
          .where((e) => e.info.hasPedPerKg)
          .map((e) => e.med.brandName)
          .toSet();
      if (needWeight.isNotEmpty) {
        alerts.add(ClinicalAlert(
          typeCode: '4.1',
          title: 'ℹ️ وزن المريض غير مُدخل',
          body: 'الأدوية دي ليها سقف جرعة بالكيلو للأطفال ومقدرناش نفحصه: '
              '${needWeight.join('، ')}.\n'
              'أدخل الوزن من تعديل بيانات المريض عشان يتفحص الجرعة.',
          severity: AlertSeverity.info,
        ));
      }
    }

    return (alerts: alerts, numericAlerted: numericAlerted);
  }

  /// السقف (mg/يوم) حسب فئة المريض لمصدر واحد.
  ///  • بالغ (≥18، أو ≥12 سنة ووزنه ≥40 كجم): adult_max_daily_mg
  ///  • طفل: الأقل من (mg/kg × الوزن) وسقف البالغين؛ لو مفيش وزن أو مفيش سقف
  ///    بالكيلو → سقف البالغين كحد أعلى مطلق (طفل فوق جرعة بالغ = غلط أكيد).
  _LimitCalc? _limitCalc(double? adult, double? pedKg, PatientSnapshot p) {
    final w = p.weightKg ?? 0.0;
    final hasW = w > 0;
    if (p.age >= 18 || (p.age >= 12 && hasW && w >= 40)) {
      return adult == null ? null : _LimitCalc(adult, 'للبالغين');
    }
    if (pedKg != null && hasW) {
      final byWeight = pedKg * w;
      if (adult != null && adult < byWeight) {
        return _LimitCalc(adult,
            'سقف البالغين (أقل من حد الوزن ${_fmtNum(byWeight)} mg)');
      }
      return _LimitCalc(
          byWeight, '${_fmtNum(pedKg)} mg/kg × ${_fmtNum(w)} kg (أطفال)');
    }
    return adult == null
        ? null
        : _LimitCalc(adult,
            'سقف البالغين كحد أعلى مطلق (مفيش سقف أطفال بالكيلو أو الوزن غير مُدخل)');
  }

  List<_SourceLimit> _sourceLimits(DoseLimitInfo info, PatientSnapshot p) {
    final out = <_SourceLimit>[];
    final src = info.primary.source;
    final primaryName = (src == null || src.isEmpty)
        ? 'الجدول الرئيسي'
        : (src.length > 70 ? '${src.substring(0, 70)}…' : src);
    final pc = _limitCalc(info.adultMaxDailyMg, info.pedMaxMgPerKgDay, p);
    if (pc != null) out.add(_SourceLimit(primaryName, pc.limitMg, pc.basis, true));
    for (final a in info.alts) {
      final c = _limitCalc(a.adultMaxDailyMg, a.pedMaxMgPerKgDay, p);
      if (c != null) out.add(_SourceLimit(a.sourceName, c.limitMg, c.basis, false));
    }
    return out;
  }

  /// تنبيهات الـ special_flag مقابل حالة المريض / طريقة الوصف.
  List<ClinicalAlert> _flagAlerts(
      MedSnapshot med, DoseLimitInfo info, PatientSnapshot patient) {
    final out = <ClinicalAlert>[];
    final seen = <String>{}; // تنبيه واحد لكل flag لكل دواء
    for (final r in info.rows) {
      final flag = r.specialFlag;
      if (flag == null || !seen.add(flag)) continue;

      if (flag == 'contraindicated_ped') {
        // ممنوع/غير موصى به تحت عمر معيّن (الافتراضي 18)
        final minAge = r.pedMinAgeYears ?? 18;
        if (patient.age >= minAge) continue;
        final sev = _parseSeverity(r.flagSeverity ?? 'moderate');
        final banned = sev == AlertSeverity.major;
        final what = banned ? 'ممنوع' : 'غير موصى به';
        final note = _cleanNotes(r.pedNote ?? r.notes, max: 220);
        out.add(ClinicalAlert(
          typeCode: banned ? '2.2' : '2.5',
          title: '${banned ? '🚫' : '⚠️'} $what في هذه الفئة العمرية: ${med.brandName}',
          body: 'عمر المريض ${patient.age} سنة — ${r.ingredient} $what تحت '
              '${_fmtNum(minAge)} سنة.${note.isEmpty ? '' : '\n$note'}',
          severity: sev,
          autoSuggestIntervention: true,
          drugA: med.brandName,
          reason: '${r.ingredient} $what تحت ${_fmtNum(minAge)} سنة '
              '(عمر المريض ${patient.age})',
        ));
      } else if (flag == 'weekly_not_daily') {
        // دواء جرعته أسبوعية (ميثوتريكسات...) والتكرار المسجّل أقصر من أسبوع
        final perDay = parseDosesPerDay(med.frequency);
        if (perDay == null || perDay <= 1 / 7 + 1e-9) continue;
        // alendronate 10mg يوميًا نظام يومي بديل صحيح؛ الأسبوعي 35/70mg بس
        if (r.ingredient == 'alendronate') {
          final u = parseDoseUnit(
              strengthRaw: med.strengthRaw, form: med.form, brandName: med.brandName);
          if (u != null && u.mgPerUnit <= 10) continue;
        }
        final note = _cleanNotes(r.notes, max: 260);
        out.add(ClinicalAlert(
          typeCode: '4.1',
          title: '⚠️ دواء أسبوعي مسجّل بتكرار أقصر: ${med.brandName}',
          body: '${r.ingredient} جرعته المعتادة أسبوعية، والتكرار المسجّل '
              '"${med.frequency}". تناوله بتكرار أقصر قد يكون خطيرًا.'
              '${note.isEmpty ? '' : '\n$note'}',
          severity: _parseSeverity(r.flagSeverity ?? 'moderate'),
          autoSuggestIntervention: true,
          drugA: med.brandName,
          reason: '${r.ingredient} جرعة أسبوعية — التكرار المسجّل "${med.frequency}"',
        ));
      } else if (flag == 'as_needed_not_chronic') {
        // دواء عند اللزوم متسجّل ضمن الأدوية المزمنة
        if (!med.isChronic) continue;
        final note = _cleanNotes(r.notes, max: 200);
        out.add(ClinicalAlert(
          typeCode: '4.2',
          title: 'ℹ️ دواء عند اللزوم مسجّل كمزمن: ${med.brandName}',
          body: '${r.ingredient} مخصص للاستخدام عند اللزوم وليس كعلاج مزمن/يومي.'
              '${note.isEmpty ? '' : '\n$note'}',
          severity: AlertSeverity.info,
          drugA: med.brandName,
        ));
      } else if (flag == 'monitored_levels') {
        // نافذة علاجية ضيقة → متابعة؛ وترتفع الأهمية لو المريض كلى/كبد
        final cond = [
          if (patient.ckdEffective) 'مرض كلوي',
          if (patient.hasLiverDisease) 'مرض كبدي',
        ].join(' و');
        final note = _cleanNotes(r.notes, max: 200);
        out.add(ClinicalAlert(
          typeCode: '6.1',
          title: '🩺 يحتاج متابعة (نافذة علاجية ضيقة): ${med.brandName}',
          body: '${r.ingredient} محتاج متابعة مستوى الدواء في الدم / المؤشرات الحيوية.'
              '${cond.isEmpty ? '' : '\nالمريض عنده $cond — احتمال تراكم الدواء.'}'
              '${note.isEmpty ? '' : '\n$note'}',
          severity: cond.isEmpty ? AlertSeverity.info : AlertSeverity.moderate,
          autoSuggestIntervention: cond.isNotEmpty,
          drugA: med.brandName,
          reason: '${r.ingredient} نافذة علاجية ضيقة'
              '${cond.isEmpty ? '' : ' مع $cond'} — متابعة مستوى الدواء',
        ));
      }
      // ul_supplement / indication_dependent / age_band_not_linear /
      // topical_or_local → بتأثر على التنبيه الرقمي بس (فوق)، مفيش تنبيه مستقل.
    }
    return out;
  }

  // ── ٥. Indication Check (1.1) ─────────────────────────────────────
  // الحكم مبني على بيانات القاعدة وبيطلع info بس: غياب الربط في القاعدة ≠ غياب
  // المؤشر الفعلي (القاعدة من RxClass وبتغطي الاستخدامات المرخّصة بس).
  //  • notListed → الدواء والتشخيص ليهم بيانات بس مفيش ربط بينهم
  //  • offLabel  → استخدام شائع غير رسمي (source = manual_offlabel)
  //  • official / unknown → مفيش تنبيه
  Future<List<ClinicalAlert>> _checkIndication(
      List<MedSnapshot> meds, PatientSnapshot patient) async {
    if (patient.diagnosisIds.isEmpty) return [];
    final alerts = <ClinicalAlert>[];
    final dx = patient.diagnosisNames.isEmpty
        ? 'التشخيص الحالي'
        : patient.diagnosisNames.join('، ');

    // الأدوية الموثّقة للتشخيص — بنجيبها مرة واحدة ولما نحتاجها بس
    String? documentedText;
    Future<String> documented() async {
      if (documentedText != null) return documentedText!;
      final list =
          await _db.documentedDrugsForDiagnoses(patient.diagnosisIds);
      documentedText = list.map((d) {
        final more = d.total > d.drugs.length
            ? ' (+${d.total - d.drugs.length} أخرى)'
            : '';
        return '• ${d.diagnosis}: ${d.drugs.join('، ')}$more';
      }).join('\n');
      return documentedText!;
    }

    for (final med in meds) {
      if (med.genericTokens.isEmpty) continue;
      final r = await _db.checkIndication(
        genericTokens: med.genericTokens,
        diagnosisIds: patient.diagnosisIds,
      );
      switch (r.status) {
        case IndicationStatus.notListed:
          final docs = await documented();
          alerts.add(ClinicalAlert(
            typeCode: '1.1',
            title: 'ℹ️ مؤشر علاجي غير موثّق: ${med.brandName}',
            body: '${med.genericName} غير مسجّل في قاعدة البيانات كعلاج لـ ($dx).\n'
                'ده لا يعني إنه غير مناسب — راجع الدواء مع حالة المريض '
                '(ممكن يكون استخدام شائع أو لعَرَض غير مغطّى في القاعدة).'
                '${docs.isEmpty ? '' : '\n\nالموثّق لهذا التشخيص:\n$docs'}',
            severity: AlertSeverity.info,
            autoSuggestIntervention: true,
            drugA: med.brandName,
          ));
        case IndicationStatus.offLabel:
          alerts.add(ClinicalAlert(
            typeCode: '1.1',
            title: 'ℹ️ استخدام غير رسمي (off-label): ${med.brandName}',
            body: '${med.genericName} ليس مؤشراً مرخّصاً لـ ($dx) لكنه استخدام شائع.'
                '${r.note != null ? '\n${r.note}' : ''}',
            severity: AlertSeverity.info,
            autoSuggestIntervention: false,
            drugA: med.brandName,
          ));
        case IndicationStatus.official:
        case IndicationStatus.unknown:
          break; // مفيش تنبيه
      }
    }
    return alerts;
  }

  // ── ٦. Beers Criteria ─────────────────────────────────────────────
  Future<List<ClinicalAlert>> _checkBeers(List<MedTokens> medTokens) async {
    // ✅ إصلاح التكرار: لو نفس الدواء موجود في الموصوفة والمزمنة معاً (نفس
    // الـ tokens) يتحسب مرة واحدة بس — نجمع كل الـ tokens الفريدة في MedTokens
    // واحدة لكل مادة فعالة، وده بيمنع Beers من الظهور مرتين لنفس الدواء.
    final seenTokens = <String>{};
    final uniqueMeds = <MedTokens>[];
    for (final m in medTokens) {
      final key = m.genericTokens.toSet().join('|');
      if (key.isEmpty || !seenTokens.add(key)) continue;
      uniqueMeds.add(m);
    }

    final results = await _db.checkBeersCriteria(uniqueMeds);
    return results
        .map((r) => ClinicalAlert(
              typeCode: '2.5',
              title: '👴 Beers Criteria: ${r.drugName}',
              body: (r.category != null && r.category!.isNotEmpty
                      ? '[${r.category}] — '
                      : '') +
                  r.rationale +
                  (r.alternative != null ? '\nالبديل: ${r.alternative}' : ''),
              severity: AlertSeverity.moderate,
              autoSuggestIntervention: false,
              drugA: r.drugName,
              reason: r.rationale,
            ))
        .toList();
  }

  // ── ٧. Local Learning ─────────────────────────────────────────────
  // ⚠️ patterns في Firestore (drug_patterns) لازم تخزّن drug_a_name و
  // drug_b_name (اسم المادة الفعالة lowercase) — الـ rxcui مبقاش بيتحدد.
  List<ClinicalAlert> _checkLocalLearning(
      List<MedSnapshot> meds, List<Map<String, dynamic>> patterns) {
    final alerts = <ClinicalAlert>[];
    final names = meds.expand((m) => m.genericTokens).toSet();

    for (final p in patterns) {
      final a = (p['drug_a_name'] as String?)?.trim().toLowerCase();
      final b = (p['drug_b_name'] as String?)?.trim().toLowerCase();
      final count = (p['occurrence_count'] as num?)?.toInt() ?? 0;
      if (a == null || b == null || count < 3) continue;
      if (names.contains(a) && names.contains(b)) {
        alerts.add(ClinicalAlert(
          typeCode: p['suggested_type_code'] as String? ?? '3.0',
          title: '💡 اقتراح من تجارب المستشفى',
          body: 'هذه التركيبة سبق التدخل فيها $count مرات في نفس المستشفى',
          severity: AlertSeverity.info,
          autoSuggestIntervention: true,
        ));
      }
    }
    return alerts;
  }

  // ── ٧. Labs (6.1) ─────────────────────────────────────────────────
  // تحاليل خارج المدى/حرجة + تحاليل أساسية ناقصة + قصور كلوي محسوب.
  // (محتاجة DB v1.0.6 — لو القديمة بترجع فاضي.)
  // التحاليل اللي مداها "هدف علاجي" (INR/مستويات الأدوية...) الخروج عن المرجع
  // العادي مش بيعتبر مشكلة بذاته → info بس إلا لو قيمة حرجة.
  static const _therapeuticTargetLabs = {
    'inr', 'aptt', 'antixa', 'vanc', 'gent', 'amik', 'digoxin', 'phenytoin',
    'valproate', 'cbz', 'pb', 'lithium', 'tacro', 'theoph',
  };

  String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Future<List<ClinicalAlert>> _checkLabs(
      PatientSnapshot patient, List<MedTokens> medTokens) async {
    final alerts = <ClinicalAlert>[];
    try {
      final recs = await _db.getRecommendedLabsFor(
          diagnosisIds: patient.diagnosisIds, drugTokens: medTokens);
      final recByCode = {for (final r in recs) r.lab.code: r};

      final latest = <String, LabResultSnapshot>{};
      for (final r in patient.labs) {
        final c = latest[r.code];
        if (c == null || r.takenAt.isAfter(c.takenAt)) latest[r.code] = r;
      }

      for (final r in latest.values) {
        final rec = recByCode[r.code];
        final lab = rec?.lab ?? await _db.getLabByCode(r.code);
        if (lab == null) continue;
        final dxNote = rec == null
            ? ''
            : '${rec.diagnoses.isEmpty ? '' : '\nمرتبط بتشخيص: ${rec.diagnoses.join('، ')}'}'
                '${rec.drugs.isEmpty ? '' : '\nمرتبط بدواء: ${rec.drugs.join('، ')}'}';
        final tgt = (rec == null || rec.targets.isEmpty)
            ? ''
            : '\nالهدف: ${rec.targets.join(' | ')}';
        final label = lab.shortName == lab.name
            ? lab.name
            : '${lab.name} (${lab.shortName})';

        // ── نوعي ──
        if (lab.isQualitative) {
          if (r.abnormal == true) {
            alerts.add(ClinicalAlert(
              typeCode: '6.1',
              title: '🧪 نتيجة غير طبيعية: ${lab.name}',
              body: 'نتيجة ${lab.name} مسجّلة غير طبيعية/إيجابية بتاريخ '
                  '${_fmtDate(r.takenAt)}.$dxNote',
              severity:
                  rec == null ? AlertSeverity.info : AlertSeverity.moderate,
              autoSuggestIntervention: true,
              reason: 'نتيجة ${lab.name} غير طبيعية',
            ));
          }
          continue;
        }

        // ── رقمي ──
        final v = r.value;
        if (v == null) continue;
        final range = await _db.getReferenceRange(lab.code,
            age: patient.age, sex: patient.sex, isPregnant: patient.isPregnant);
        final st = evaluateLabValue(lab, range, v);
        if (st == LabStatus.normal || st == LabStatus.unknown) continue;

        final critical =
            st == LabStatus.criticalLow || st == LabStatus.criticalHigh;
        final dir = switch (st) {
          LabStatus.criticalLow => 'منخفض جداً (قيمة حرجة)',
          LabStatus.criticalHigh => 'مرتفع جداً (قيمة حرجة)',
          LabStatus.low => 'منخفض',
          _ => 'مرتفع',
        };
        final val = '${_fmtNum(v)} ${lab.unit}'.trim();
        final lines = <String>[
          'القيمة: $val بتاريخ ${_fmtDate(r.takenAt)}',
          if (range != null && range.isNumeric)
            'المدى المرجعي: ${range.text(lab.unit)}',
          if (critical)
            'حد القيمة الحرجة: ${st == LabStatus.criticalLow ? '<' : '>'} '
                '${_fmtNum(st == LabStatus.criticalLow ? lab.criticalLow! : lab.criticalHigh!)}',
          if (range?.sexAssumed ?? false)
            'ℹ️ جنس المريض غير مسجّل — المدى بيشمل الذكور والإناث',
          if (range?.note != null) range!.note!,
          if (_therapeuticTargetLabs.contains(lab.code) && !critical)
            'ℹ️ ممكن يكون ضمن الهدف العلاجي لو المريض على الدواء المقابل.',
        ];
        final sev = critical
            ? AlertSeverity.major
            : (_therapeuticTargetLabs.contains(lab.code) || rec == null)
                ? AlertSeverity.info
                : AlertSeverity.moderate;
        alerts.add(ClinicalAlert(
          typeCode: '6.1',
          title: '🧪 $label $dir: $val',
          body: lines.join('\n') + tgt + dxNote,
          severity: sev,
          autoSuggestIntervention:
              sev == AlertSeverity.major || sev == AlertSeverity.moderate,
          reason: '$label $dir ($val'
              '${range != null && range.isNumeric ? ' — المدى ${range.text(lab.unit)}' : ''})',
        ));
      }

      // ── تحاليل أساسية لم تُسجَّل ──
      final missing = recs
          .where((r) =>
              r.priority == 'essential' && !latest.containsKey(r.lab.code))
          .toList();
      if (missing.isNotEmpty) {
        final shown = missing.take(10).toList();
        alerts.add(ClinicalAlert(
          typeCode: '6.1',
          title: '🧪 تحاليل أساسية للمتابعة لم تُسجَّل (${missing.length})',
          body: shown
                  .map((m) =>
                      '• ${m.lab.shortName}: '
                      '${m.rationales.isEmpty ? '' : m.rationales.first}'
                      '${m.frequency.isEmpty ? '' : ' [${m.frequency}]'}'
                      '${m.drugs.isEmpty ? '' : ' 💊'}')
                  .join('\n') +
              (missing.length > shown.length
                  ? '\n… و${missing.length - shown.length} أخرى'
                  : ''),
          severity: AlertSeverity.info,
        ));
      }

      // ── قصور كلوي محسوب من الكرياتينين ──
      final crcl = patient.crcl;
      if (crcl != null && crcl < 60 && !patient.hasCkd) {
        alerts.add(ClinicalAlert(
          typeCode: '6.1',
          title: '🩺 قصور كلوي محسوب: CrCl ≈ ${_fmtNum(crcl)} mL/min',
          body: 'محسوب بمعادلة Cockcroft-Gault من آخر كرياتينين مسجّل (بالوزن الفعلي) '
              'وهو أقل من 60 mL/min، والمريض غير مسجّل كحالة CKD.\n'
              'تم تفعيل فحص تعديل الجرعات الكلوي تلقائياً — راجع الأدوية المطروحة بالكلى.',
          severity: AlertSeverity.moderate,
          autoSuggestIntervention: true,
          reason: 'قصور كلوي محسوب CrCl ≈ ${_fmtNum(crcl)} mL/min',
        ));
      }
    } catch (e) {
      // ما نكسرش باقي التنبيهات
    }
    return alerts;
  }

  // ── تنبيهات الأمبولات/الفيالات المضافة على محاليل وريدية رغم عدم صلاحيتها
  // للحقن الوريدي (2.3 — طريقة إعطاء غير مناسبة). المستخدم وافق على الاستكمال
  // وقت الإضافة، فالتنبيه بيفضل ظاهر في تبويب التنبيهات.
  List<ClinicalAlert> checkFluidAdditives(
      List<({String fluid, String drug, String warning})> items) {
    return items
        .map((i) => ClinicalAlert(
              typeCode: '2.3',
              title: '💉 غير مناسب للحقن الوريدي: ${i.drug}',
              body: 'أُضيف على "${i.fluid}".\n${i.warning}',
              severity: AlertSeverity.major,
              autoSuggestIntervention: true,
              drugA: i.drug,
              reason: i.warning,
            ))
        .toList();
  }

  // ── Helpers ──────────────────────────────────────────────────────
  AlertSeverity _parseSeverity(String s) => switch (s.toLowerCase()) {
        'major' => AlertSeverity.major,
        'moderate' => AlertSeverity.moderate,
        'minor' => AlertSeverity.minor,
        _ => AlertSeverity.info,
      };

  /// الحد الأقصى اليومي بالـ mg حسب فئة المريض.
  /// - الرضع (age == 0): null
  /// - الأطفال: ped_max_daily فقط — وحدات per-kg في القاعدة مش متسقة
  ///   (mg/kg لجرعة ولا ليوم؟) فمش بنحسب بالوزن لحد جدول generic_dose_limits
  /// - الكبار وكبار السن: adult_max_daily (elderly_dose_max جرعة واحدة مش حد يومي)
  double? _maxDailyForPatient(DoseInfo dose, PatientSnapshot patient) {
    if (patient.age <= 0) return null;
    if (patient.age <= 16) return dose.pedMaxDaily;
    return dose.adultMaxDaily;
  }
}
