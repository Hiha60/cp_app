// ─────────────────────────────────────────────────────────────────────────────
//  DRUG CLASS FAMILIES — لفحص الحساسية المتقاطعة (Cross-Reactivity)
// ─────────────────────────────────────────────────────────────────────────────
// ⚠️ القاعدة المحلية (cp_app_medical.db) مفيهاش عمود drug_class/atc_code في
// جدول generics، يعني مفيش تصنيف عائلات جاهز فيها. القائمة دي منسّقة يدويًا
// (مش شاملة كل الأدوية) وبتغطي العائلات الأكتر شيوعًا في تسجيل الحساسية.
// أسماء المواد الفعالة هنا اتوثّقت فعليًا إنها موجودة في normalized_generics
// بتاعة القاعدة الحالية. لو عايز تضيف عيلة أو مادة جديدة، ضيفها هنا بس.

class DrugClassGroup {
  final String nameAr;
  final List<String> genericTokens; // lowercase — زي ما بتتخزن في normalized_generics
  const DrugClassGroup({required this.nameAr, required this.genericTokens});
}

const kDrugClasses = <DrugClassGroup>[
  DrugClassGroup(nameAr: 'بنسلينات (Penicillins)', genericTokens: [
    'amoxicillin', 'ampicillin', 'penicillin g', 'penicillin g procaine',
    'benzathine penicillin g', 'phenoxymethyl penicillin', 'cloxacillin',
    'dicloxacillin', 'flucloxacillin', 'piperacillin',
    'clavulanic acid', 'clavulanate',
  ]),
  DrugClassGroup(nameAr: 'سيفالوسبورينات (Cephalosporins)', genericTokens: [
    'cefaclor', 'cefadroxil', 'cefalexin', 'cefazolin', 'cefapirin',
    'cefdinir', 'cefditoren', 'cefepime', 'cefixime', 'cefoperazone',
    'cefotaxime', 'cefoxitin', 'cefpirome', 'cefpodoxime', 'cefprozil',
    'ceftazidime', 'ceftibuten', 'ceftriaxone', 'cefuroxime',
    'ceftaroline fosamil', 'ceftolozane',
  ]),
  DrugClassGroup(nameAr: 'كاربابينيمات (Carbapenems)', genericTokens: [
    'ertapenem', 'imipenem', 'meropenem',
  ]),
  DrugClassGroup(nameAr: 'سلفوناميدات (Sulfonamides)', genericTokens: [
    'sulfamethoxazole', 'sulfacetamide', 'silver sulfadiazine',
    'phthalylsulfathiazole', 'trimethoprim',
  ]),
  DrugClassGroup(nameAr: 'أمينوجليكوزيدات (Aminoglycosides)', genericTokens: [
    'gentamicin', 'amikacin', 'tobramycin', 'streptomycin', 'neomycin', 'kanamycin',
  ]),
  DrugClassGroup(nameAr: 'ماكروليدات (Macrolides)', genericTokens: [
    'azithromycin', 'clarithromycin', 'erythromycin', 'roxithromycin',
    'spiramycin', 'clindamycin',
  ]),
  DrugClassGroup(nameAr: 'فلوروكينولونات (Fluoroquinolones)', genericTokens: [
    'ciprofloxacin', 'levofloxacin', 'moxifloxacin', 'ofloxacin', 'norfloxacin',
    'gatifloxacin', 'gemifloxacin', 'lomefloxacin', 'sparfloxacin',
    'pefloxacin', 'nadifloxacin',
  ]),
  DrugClassGroup(nameAr: 'تتراسيكلينات (Tetracyclines)', genericTokens: [
    'tetracycline', 'doxycycline', 'oxytetracycline', 'tigecycline',
  ]),
  DrugClassGroup(nameAr: 'مضادات التهاب غير ستيرويدية (NSAIDs)', genericTokens: [
    'ibuprofen', 'diclofenac', 'ketoprofen', 'naproxen', 'indomethacin',
    'mefenamic acid', 'piroxicam', 'meloxicam', 'celecoxib', 'etoricoxib',
    'nimesulide', 'ketorolac', 'dexketoprofen', 'flurbiprofen', 'fenoprofen',
    'loxoprofen', 'dexibuprofen', 'aspirin',
  ]),
];

/// اسم العيلة اللي المادة الفعالة دي تابعة لها (null لو مش معروفة/مصنّفة)
String? drugClassFor(String genericToken) {
  final t = genericToken.trim().toLowerCase();
  for (final c in kDrugClasses) {
    if (c.genericTokens.contains(t)) return c.nameAr;
  }
  return null;
}

/// أول عيلة معروفة من ضمن مجموعة توكينز دواء معيّن (للأدوية المركّبة)
String? firstKnownClassFor(List<String> genericTokens) {
  for (final t in genericTokens) {
    final c = drugClassFor(t);
    if (c != null) return c;
  }
  return null;
}

/// كل المواد الفعالة التابعة لنفس عيلة المادة المعطاة (شاملة هي)
List<String> tokensInSameClass(String genericToken) {
  final t = genericToken.trim().toLowerCase();
  for (final c in kDrugClasses) {
    if (c.genericTokens.contains(t)) return List<String>.from(c.genericTokens);
  }
  return [t];
}
