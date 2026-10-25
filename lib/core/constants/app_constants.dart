import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
//  COLORS
// ─────────────────────────────────────────────
class AppColors {
  AppColors._();

  static const primary     = Color(0xFF1565C0); // Medical Blue
  static const primaryDark = Color(0xFF003c8f);
  static const primaryLight= Color(0xFF5e92f3);
  static const surface     = Color(0xFFF5F7FA);
  static const card        = Colors.white;
  static const textPrimary = Color(0xFF1A1A2E);
  static const textSecond  = Color(0xFF6B7280);
  static const success     = Color(0xFF22C55E);
  static const warning     = Color(0xFFF59E0B);
  static const danger      = Color(0xFFEF4444);
  static const info        = Color(0xFF3B82F6);
  static const adminOwn    = Color(0xFF7C3AED); // بنفسجي — تدخلات الأدمن الشخصية
}

// ─────────────────────────────────────────────
//  ROLES
// ─────────────────────────────────────────────
class UserRole {
  static const superAdmin = 'super_admin';
  static const admin      = 'admin';
  static const pharmacist = 'pharmacist';
  static const doctor     = 'doctor';
}

// ─────────────────────────────────────────────
//  PATIENT STATUS
// ─────────────────────────────────────────────
class PatientStatus {
  static const active     = 'active';
  static const discharged = 'discharged';
}

// ─────────────────────────────────────────────
//  INTERVENTION TYPES  (26 نوع، 7 فئات)
// ─────────────────────────────────────────────
class InterventionType {
  final String code;
  final String categoryAr;
  final String nameEn;
  final String nameAr;
  final String commentTemplate; // المتغيرات: [DRUG], [ALT], [CONDITION], [OLD], [NEW], [REASON] ...

  const InterventionType({
    required this.code,
    required this.categoryAr,
    required this.nameEn,
    required this.nameAr,
    required this.commentTemplate,
  });
}

const kInterventionTypes = <InterventionType>[
  // ── Unnecessary Drug ──────────────────────
  InterventionType(code:'1.1', categoryAr:'دواء غير ضروري',   nameEn:'No valid indication',           nameAr:'لا يوجد مؤشر علاجي',         commentTemplate:'تم إيقاف [DRUG] لعدم وجود مؤشر علاجي واضح لدى المريض'),
  InterventionType(code:'1.2', categoryAr:'دواء غير ضروري',   nameEn:'Therapeutic Duplication',       nameAr:'تكرار علاجي',                 commentTemplate:'تم إيقاف [DRUG] تجنباً للتكرار العلاجي، حيث يؤدي نفس دور [ALT]'),
  InterventionType(code:'1.3', categoryAr:'دواء غير ضروري',   nameEn:'Non-drug therapy preferred',    nameAr:'يُفضّل العلاج غير الدوائي',  commentTemplate:'تم إيقاف [DRUG] والتوصية بالعلاج غير الدوائي'),
  // ── Needs Drug ────────────────────────────
  InterventionType(code:'1.4', categoryAr:'يحتاج دواء',       nameEn:'Untreated indication',          nameAr:'حالة غير معالجة',             commentTemplate:'تمت إضافة [DRUG] لعلاج [CONDITION] غير المعالج لدى المريض'),
  InterventionType(code:'1.5', categoryAr:'يحتاج دواء',       nameEn:'Preventive drug required',      nameAr:'دواء وقائي مطلوب',           commentTemplate:'تمت إضافة [DRUG] كعلاج وقائي للحد من خطر تطور [CONDITION]'),
  InterventionType(code:'1.6', categoryAr:'يحتاج دواء',       nameEn:'Abrupt discontinuation',        nameAr:'إيقاف مفاجئ',                commentTemplate:'تم التنبيه على ضرورة التوقف التدريجي عن [DRUG] تجنباً لأعراض الانسحاب'),
  InterventionType(code:'1.7', categoryAr:'يحتاج دواء',       nameEn:'Additional drug therapy needed',nameAr:'علاج إضافي مطلوب',           commentTemplate:'تمت إضافة [DRUG] لأن حالة [CONDITION] تستلزم علاجاً دوائياً إضافياً'),
  // ── Selection ─────────────────────────────
  InterventionType(code:'2.1', categoryAr:'اختيار الدواء',    nameEn:'Allergy',                       nameAr:'حساسية',                     commentTemplate:'تم إيقاف [DRUG] لوجود حساسية واستبداله بـ [ALT]'),
  InterventionType(code:'2.2', categoryAr:'اختيار الدواء',    nameEn:'Contraindication',              nameAr:'موانع استخدام',              commentTemplate:'تم إيقاف [DRUG] لوجود تعارض مع حالة [CONDITION] واستبداله بـ [ALT]'),
  InterventionType(code:'2.3', categoryAr:'اختيار الدواء',    nameEn:'Inappropriate route/form',      nameAr:'طريقة إعطاء غير مناسبة',     commentTemplate:'تم تغيير طريقة إعطاء [DRUG] من [OLD] إلى [NEW]'),
  InterventionType(code:'2.4', categoryAr:'اختيار الدواء',    nameEn:'More effective drug available', nameAr:'يوجد بديل أفضل',             commentTemplate:'تم استبدال [DRUG] بـ [ALT] لكونه الأكثر فعالية وفقاً للإرشادات'),
  InterventionType(code:'2.5', categoryAr:'اختيار الدواء',    nameEn:'Alert / Warning',               nameAr:'تنبيه / تحذير',              commentTemplate:'تنبيه: استخدام [DRUG] يستوجب الحذر لوجود [REASON]'),
  // ── Drug Interactions ─────────────────────
  InterventionType(code:'3.0', categoryAr:'التداخلات الدوائية',nameEn:'Drug Interaction',             nameAr:'تداخل دوائي',                commentTemplate:'تم التدخل بخصوص التداخل الدوائي بين [DRUG] و[ALT] والتوصية بـ [REASON]'),
  // ── Dosing Regimen ────────────────────────
  InterventionType(code:'4.1', categoryAr:'نظام الجرعة',      nameEn:'Inappropriate dose/interval',   nameAr:'جرعة أو تكرار غير مناسب',   commentTemplate:'تم تعديل جرعة [DRUG] من [OLD] إلى [NEW] بناءً على [REASON]'),
  InterventionType(code:'4.2', categoryAr:'نظام الجرعة',      nameEn:'Inappropriate duration',        nameAr:'مدة علاج غير مناسبة',        commentTemplate:'تم تعديل مدة العلاج بـ [DRUG] من [OLD] إلى [NEW]'),
  // ── Instructions ──────────────────────────
  InterventionType(code:'5.1', categoryAr:'تعليمات الإعطاء',  nameEn:'Administration rate',           nameAr:'معدل الإعطاء',               commentTemplate:'تم التنبيه على ضرورة إعطاء [DRUG] بمعدل [REASON]'),
  InterventionType(code:'5.2', categoryAr:'تعليمات الإعطاء',  nameEn:'Dilution instructions',         nameAr:'تعليمات التخفيف',            commentTemplate:'تم التنبيه على ضرورة تخفيف [DRUG] في [OLD] بتركيز [NEW]'),
  InterventionType(code:'5.3', categoryAr:'تعليمات الإعطاء',  nameEn:'Incompatibility',               nameAr:'عدم توافق',                  commentTemplate:'تم التنبيه على عدم إمكانية إعطاء [DRUG] و[ALT] في نفس الخط الوريدي'),
  InterventionType(code:'5.4', categoryAr:'تعليمات الإعطاء',  nameEn:'Administration time',           nameAr:'توقيت الإعطاء',              commentTemplate:'تم التنبيه على ضرورة إعطاء [DRUG] [REASON]'),
  // ── Monitoring ────────────────────────────
  InterventionType(code:'6.1', categoryAr:'المتابعة',          nameEn:'Monitoring needed',             nameAr:'متابعة مطلوبة',              commentTemplate:'تم التوصية بمتابعة [REASON] أثناء استخدام [DRUG]'),
  InterventionType(code:'6.2', categoryAr:'المتابعة',          nameEn:'Adverse drug reaction',         nameAr:'تأثير جانبي غير مرغوب',      commentTemplate:'تم رصد [OLD] كأثر غير مرغوب لـ [DRUG] والتوصية بـ [REASON]'),
  // ── Adherence ─────────────────────────────
  InterventionType(code:'7.1', categoryAr:'الالتزام بالعلاج', nameEn:'Patient misunderstands instructions', nameAr:'المريض لا يفهم التعليمات', commentTemplate:'تم تثقيف المريض وشرح تعليمات استخدام [DRUG]'),
  InterventionType(code:'7.2', categoryAr:'الالتزام بالعلاج', nameEn:'Patient forgets medication',    nameAr:'المريض ينسى الدواء',         commentTemplate:'تم وضع خطة تذكير للمريض لضمان انتظام تناول [DRUG]'),
  InterventionType(code:'7.3', categoryAr:'الالتزام بالعلاج', nameEn:'Patient refuses medication',    nameAr:'المريض يرفض الدواء',         commentTemplate:'تم مناقشة المريض حول أهمية [DRUG]'),
  InterventionType(code:'7.4', categoryAr:'الالتزام بالعلاج', nameEn:'Patient cannot afford drug',    nameAr:'تكلفة الدواء مرتفعة',        commentTemplate:'تم استبدال [DRUG] بـ [ALT] كبديل أقل تكلفة'),
  InterventionType(code:'7.5', categoryAr:'الالتزام بالعلاج', nameEn:'Drug not available',            nameAr:'الدواء غير متاح',            commentTemplate:'تم استبدال [DRUG] بـ [ALT] كبديل متاح'),
  InterventionType(code:'7.6', categoryAr:'الالتزام بالعلاج', nameEn:'Patient cannot self-administer',nameAr:'المريض لا يستطيع أخذ الدواء بنفسه', commentTemplate:'تم تغيير طريقة إعطاء [DRUG] من [OLD] إلى [NEW] لملاءمتها لقدرات المريض'),
];

// helper — جيب النوع بالـ code
InterventionType? findInterventionByCode(String code) =>
    kInterventionTypes.where((t) => t.code == code).firstOrNull;

// helper — جيب كل أنواع فئة معينة
List<InterventionType> interventionsByCategory(String categoryAr) =>
    kInterventionTypes.where((t) => t.categoryAr == categoryAr).toList();

// helper — كل الفئات (بدون تكرار)
List<String> get kInterventionCategories =>
    kInterventionTypes.map((t) => t.categoryAr).toSet().toList();

// ─────────────────────────────────────────────
//  DOSAGE FORMS  (chips)
// ─────────────────────────────────────────────
const kDosageForms = [
  'قرص', 'كبسولة', 'فيال', 'شراب', 'أمبول',
  'قطرة', 'بخاخ', 'مرهم', 'تحميلة', 'رقعة جلدية',
];

// ─────────────────────────────────────────────
//  FREQUENCIES (chips)
// ─────────────────────────────────────────────
const kFrequencies = [
  'مرة يوميا', 'مرتين يوميا', '3 مرات يوميا', '4 مرات يوميا', '5 مرات يوميا',
  'يوم بعد يوم', 'مرة كل 3 أيام', 'مرة كل أسبوع', 'مرة كل شهر',
];

// ─────────────────────────────────────────────
//  ALLERGY REACTION TYPES
// ─────────────────────────────────────────────
const kAllergyTypes = [
  'Rash', 'Anaphylaxis', 'Angioedema', 'Urticaria', 'Unknown',
];

// ─────────────────────────────────────────────
//  AGE GROUPS for comorbidities
// ─────────────────────────────────────────────
const kNeonatalComorbidities  = ['RDS', 'Neonatal Jaundice', 'Neonatal Sepsis', 'Hypoglycemia'];
const kPediatricComorbidities = ['Type 1 DM', 'Asthma', 'Epilepsy', 'Celiac Disease', 'ADHD'];
const kAdultComorbidities     = ['HTN', 'DM Type 2', 'CKD', 'Heart Failure', 'COPD', 'Hypothyroidism', 'Atrial Fibrillation', 'Epilepsy', 'Asthma', 'Liver Cirrhosis'];
const kElderlyComorbidities   = ['HTN', 'Heart Failure', 'CKD', 'COPD', 'Atrial Fibrillation', 'Osteoporosis', 'DM Type 2', 'Dementia', 'Parkinson'];

/// [months] = الشهور الإضافية (0–11). حديث الولادة = أقل من سنة وعمره
/// شهر أو أقل (أو لسه ما اتكتبش شهور). الرضيع من شهرين لـ 11 شهر = أطفال.
List<String> comorbiditiesForAge(int age, {int months = 0}) {
  if (age <= 0 && months <= 1) return kNeonatalComorbidities;
  if (age <= 16) return kPediatricComorbidities;
  if (age <= 64) return kAdultComorbidities;
  return kElderlyComorbidities;
}

// ─────────────────────────────────────────────
//  اختصارات التشخيصات / الأمراض المزمنة — مرتبة حسب أولوية السن
//  label = اللي بيظهر على الزرار، term = كلمة البحث في جدول diagnoses
//  (بيتم ربطها بأول تشخيص مطابق في القاعدة، ولو ملقاش بيستخدم label)
// ─────────────────────────────────────────────
class DxShortcut {
  final String label;
  final String term;
  const DxShortcut(this.label, this.term);
}

enum AgeGroup { neonate, child, adult, elderly }

AgeGroup ageGroupOf(int age, {int months = 0}) {
  if (age <= 0 && months <= 1) return AgeGroup.neonate;
  if (age <= 16) return AgeGroup.child;
  if (age <= 64) return AgeGroup.adult;
  return AgeGroup.elderly;
}

const _kComorbShortcuts = <AgeGroup, List<DxShortcut>>{
  AgeGroup.neonate: [
    DxShortcut('Prematurity', 'prematurity'),
    DxShortcut('RDS', 'respiratory distress'),
    DxShortcut('Neonatal Jaundice', 'neonatal jaundice'),
    DxShortcut('Neonatal Sepsis', 'neonatal sepsis'),
    DxShortcut('Hypoglycemia', 'hypoglycemia'),
  ],
  AgeGroup.child: [
    DxShortcut('Asthma', 'asthma'),
    DxShortcut('Type 1 DM', 'type 1 diabetes'),
    DxShortcut('Epilepsy', 'epilepsy'),
    DxShortcut('Allergic Rhinitis', 'allergic rhinitis'),
    DxShortcut('Iron Deficiency Anemia', 'iron deficiency'),
    DxShortcut('Congenital Heart Disease', 'congenital heart'),
    DxShortcut('ADHD', 'attention deficit'),
    DxShortcut('Celiac Disease', 'celiac'),
    DxShortcut('Cerebral Palsy', 'cerebral palsy'),
    DxShortcut('Sickle Cell', 'sickle cell'),
  ],
  AgeGroup.adult: [
    DxShortcut('HTN', 'hypertension'),
    DxShortcut('DM Type 2', 'type 2 diabetes'),
    DxShortcut('Asthma', 'asthma'),
    DxShortcut('CKD', 'chronic kidney'),
    DxShortcut('Heart Failure', 'heart failure'),
    DxShortcut('COPD', 'chronic obstructive'),
    DxShortcut('Hypothyroidism', 'hypothyroidism'),
    DxShortcut('Epilepsy', 'epilepsy'),
    DxShortcut('Atrial Fibrillation', 'atrial fibrillation'),
    DxShortcut('Liver Cirrhosis', 'cirrhosis'),
  ],
  AgeGroup.elderly: [
    DxShortcut('HTN', 'hypertension'),
    DxShortcut('DM Type 2', 'type 2 diabetes'),
    DxShortcut('Heart Failure', 'heart failure'),
    DxShortcut('CKD', 'chronic kidney'),
    DxShortcut('COPD', 'chronic obstructive'),
    DxShortcut('Atrial Fibrillation', 'atrial fibrillation'),
    DxShortcut('Ischemic Heart Disease', 'ischemic heart'),
    DxShortcut('Osteoporosis', 'osteoporosis'),
    DxShortcut('Dementia', 'dementia'),
    DxShortcut('Parkinson', 'parkinson'),
  ],
};

const _kDxShortcuts = <AgeGroup, List<DxShortcut>>{
  AgeGroup.neonate: [
    DxShortcut('Neonatal Sepsis', 'neonatal sepsis'),
    DxShortcut('Neonatal Jaundice', 'neonatal jaundice'),
    DxShortcut('RDS', 'respiratory distress'),
    DxShortcut('Prematurity', 'prematurity'),
    DxShortcut('Hypoglycemia', 'hypoglycemia'),
  ],
  AgeGroup.child: [
    DxShortcut('Gastroenteritis', 'gastroenteritis'),
    DxShortcut('Pneumonia', 'pneumonia'),
    DxShortcut('Tonsillitis', 'tonsillitis'),
    DxShortcut('Otitis Media', 'otitis media'),
    DxShortcut('Bronchiolitis', 'bronchiolitis'),
    DxShortcut('Asthma', 'asthma'),
    DxShortcut('UTI', 'urinary tract infection'),
    DxShortcut('Febrile Convulsion', 'febrile'),
    DxShortcut('Iron Deficiency Anemia', 'iron deficiency'),
    DxShortcut('Type 1 DM', 'type 1 diabetes'),
  ],
  AgeGroup.adult: [
    DxShortcut('HTN', 'hypertension'),
    DxShortcut('DM Type 2', 'type 2 diabetes'),
    DxShortcut('Pneumonia', 'pneumonia'),
    DxShortcut('UTI', 'urinary tract infection'),
    DxShortcut('Gastroenteritis', 'gastroenteritis'),
    DxShortcut('Asthma', 'asthma'),
    DxShortcut('Sepsis', 'sepsis'),
    DxShortcut('Cellulitis', 'cellulitis'),
    DxShortcut('Pyelonephritis', 'pyelonephritis'),
    DxShortcut('DKA', 'ketoacidosis'),
  ],
  AgeGroup.elderly: [
    DxShortcut('HTN', 'hypertension'),
    DxShortcut('DM Type 2', 'type 2 diabetes'),
    DxShortcut('Heart Failure', 'heart failure'),
    DxShortcut('Pneumonia', 'pneumonia'),
    DxShortcut('UTI', 'urinary tract infection'),
    DxShortcut('COPD', 'chronic obstructive'),
    DxShortcut('Acute Coronary Syndrome', 'acute coronary'),
    DxShortcut('Stroke', 'stroke'),
    DxShortcut('AKI', 'acute kidney'),
    DxShortcut('Sepsis', 'sepsis'),
  ],
};

List<DxShortcut> comorbidityShortcutsForAge(int age, {int months = 0}) =>
    _kComorbShortcuts[ageGroupOf(age, months: months)]!;

List<DxShortcut> diagnosisShortcutsForAge(int age, {int months = 0}) =>
    _kDxShortcuts[ageGroupOf(age, months: months)]!;

/// كلمات الأولوية (بالترتيب) لترتيب نتايج البحث حسب السن
List<String> dxPriorityTermsForAge(int age, {int months = 0}) {
  final g = ageGroupOf(age, months: months);
  return {
    ..._kDxShortcuts[g]!.map((e) => e.term),
    ..._kComorbShortcuts[g]!.map((e) => e.term),
  }.toList();
}

/// مرض كلوي مزمن / كبدي — بيتعرّف على الاسم المختصر والاسم الكامل (من القاعدة)
bool isCkdName(String c) {
  final l = c.toLowerCase();
  return l.contains('ckd') ||
      l.contains('chronic kidney') ||
      l.contains('renal failure') ||
      l.contains('renal insufficiency') ||
      l.contains('esrd') ||
      l.contains('end stage renal') ||
      l.contains('end-stage renal');
}

bool isLiverDiseaseName(String c) {
  final l = c.toLowerCase();
  return l.contains('liver') || l.contains('cirrhosis') || l.contains('hepatic');
}
