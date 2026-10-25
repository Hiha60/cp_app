// core/constants/intervention_fields.dart
//
// بيحدد لكل نوع تدخل: إيه الحقول اللي تظهر، ومن أي مصدر اختياراتها.

/// مصدر اختيارات كل حقل
enum FieldSource {
  prescribed, // الأدوية الموصوفة فقط
  allMeds, // الموصوفة + المزمنة
  otherMeds, // نفس allMeds بدون الدواء الأول (+ أعشاب المريض في التداخل)
  dbDrug, // بحث في قاعدة الأدوية (دواء جديد/بديل)
  condition, // تشخيصات + أعراض + أمراض مزمنة للمريض
  recommendation, // توصية التداخل: إيقاف/تغيير أحد الدواءين
  form, // أشكال صيدلية (مع اقتراح أشكال نفس الدواء)
  text, // كتابة حرة
}

class VarSpec {
  final String token; // DRUG / ALT / OLD / NEW / CONDITION / REASON
  final String label;
  final FieldSource source;
  final bool isRequired;
  const VarSpec(this.token, this.label, this.source, {this.isRequired = true});
}

const _drug = VarSpec('DRUG', 'اسم الدواء', FieldSource.allMeds);
const _drugRx =
    VarSpec('DRUG', 'اسم الدواء (من الموصوفة فقط)', FieldSource.prescribed);
const _drugNew = VarSpec('DRUG', 'الدواء المضاف', FieldSource.dbDrug);
const _altDb = VarSpec('ALT', 'البديل', FieldSource.dbDrug);
const _cond = VarSpec('CONDITION', 'الحالة', FieldSource.condition);

const kInterventionFields = <String, List<VarSpec>>{
  // ── دواء غير ضروري ──────────────────────────────
  '1.1': [_drugRx],
  '1.2': [
    VarSpec('DRUG', 'الدواء المراد إيقافه', FieldSource.allMeds),
    VarSpec('ALT', 'الدواء المكرر معه', FieldSource.otherMeds),
  ],
  '1.3': [_drugRx],
  // ── يحتاج دواء ──────────────────────────────────
  '1.4': [_drugNew, _cond],
  '1.5': [_drugNew, _cond],
  '1.6': [_drug],
  '1.7': [_drugNew, _cond],
  // ── اختيار الدواء ───────────────────────────────
  '2.1': [_drug, _altDb],
  '2.2': [_drug, _cond, _altDb],
  '2.3': [
    _drug,
    VarSpec('OLD', 'الشكل الحالي', FieldSource.text),
    VarSpec('NEW', 'الشكل الأنسب', FieldSource.form),
  ],
  '2.4': [_drug, _altDb],
  '2.5': [_drug, VarSpec('REASON', 'سبب التنبيه', FieldSource.text)],
  // ── تداخل دوائي ─────────────────────────────────
  '3.0': [
    VarSpec('DRUG', 'الدواء الأول', FieldSource.allMeds),
    VarSpec('ALT', 'الدواء الثاني', FieldSource.otherMeds),
    VarSpec('NEW', 'التوصية', FieldSource.recommendation),
    VarSpec('REASON', 'السبب (نوع التداخل وضرره)', FieldSource.text),
  ],
  // ── نظام الجرعة ─────────────────────────────────
  '4.1': [
    _drug,
    VarSpec('OLD', 'الجرعة الحالية', FieldSource.text),
    VarSpec('NEW', 'الجرعة المقترحة', FieldSource.text),
    VarSpec('REASON', 'بناءً على', FieldSource.text),
  ],
  '4.2': [
    _drug,
    VarSpec('OLD', 'المدة الحالية', FieldSource.text),
    VarSpec('NEW', 'المدة المقترحة', FieldSource.text),
  ],
  // ── تعليمات الإعطاء ─────────────────────────────
  '5.1': [_drug, VarSpec('REASON', 'معدل الإعطاء', FieldSource.text)],
  '5.2': [
    _drug,
    VarSpec('OLD', 'المذيب', FieldSource.text),
    VarSpec('NEW', 'التركيز', FieldSource.text),
  ],
  '5.3': [
    VarSpec('DRUG', 'الدواء الأول', FieldSource.allMeds),
    VarSpec('ALT', 'الدواء الثاني', FieldSource.otherMeds),
  ],
  '5.4': [
    _drug,
    VarSpec('REASON', 'التوقيت (مثلاً: قبل الأكل)', FieldSource.text),
  ],
  // ── المتابعة ────────────────────────────────────
  '6.1': [_drug, VarSpec('REASON', 'المطلوب متابعته', FieldSource.text)],
  '6.2': [
    _drug,
    VarSpec('OLD', 'الأثر الجانبي', FieldSource.text),
    VarSpec('REASON', 'التوصية', FieldSource.text),
  ],
  // ── الالتزام بالعلاج ────────────────────────────
  '7.1': [_drug],
  '7.2': [_drug],
  '7.3': [_drug],
  '7.4': [_drug, _altDb],
  '7.5': [_drug, _altDb],
  '7.6': [
    _drug,
    VarSpec('OLD', 'الطريقة/الشكل الحالي', FieldSource.text),
    VarSpec('NEW', 'الطريقة/الشكل الجديد', FieldSource.form),
  ],
};
