// المحاليل الوريدية — القائمة الثابتة + التصنيف
import '../../data/models/patient_model.dart';
import '../services/alert_engine.dart';

class FluidDef {
  final String id, name, group;
  final bool main; // يظهر كاختيار واضح (باقي القائمة تحت "أخرى")
  const FluidDef(this.id, this.name, this.group, {this.main = false});
}

const kFluidGroupTitles = <String, String>{
  'salt': 'محاليل الملح',
  'dex': 'محاليل الجلوكوز',
  'dexsalt': 'جلوكوز ملحي',
  'dexk': 'جلوكوز + بوتاسيوم',
  'saltk': 'ملح + بوتاسيوم',
  'combo': 'محاليل مركبة (أسماء تجارية)',
  'ringer': 'محاليل رينجر',
  'mannitol': 'مانيتول',
  'albumin': 'ألبيومين',
  'bicarb': 'بيكربونات الصوديوم',
  'lactate': 'لاكتات الصوديوم',
};

const kIvFluids = <FluidDef>[
  // ── ملح ──
  FluidDef('ns045', 'محلول ملح 0.45%', 'salt'),
  FluidDef('ns09', 'محلول ملح 0.9% (Normal Saline)', 'salt', main: true),
  FluidDef('ns27', 'محلول ملح 2.7%', 'salt'),
  FluidDef('ns3', 'محلول ملح 3%', 'salt'),
  FluidDef('ns10', 'محلول ملح 10%', 'salt'),
  // ── جلوكوز ──
  FluidDef('d5', 'محلول جلوكوز 5%', 'dex', main: true),
  FluidDef('d10', 'محلول جلوكوز 10%', 'dex'),
  FluidDef('d20', 'محلول جلوكوز 20%', 'dex'),
  FluidDef('d25', 'محلول جلوكوز 25%', 'dex'),
  FluidDef('d40', 'محلول جلوكوز 40%', 'dex'),
  FluidDef('d50', 'محلول جلوكوز 50%', 'dex'),
  // ── جلوكوز ملحي ──
  FluidDef('d5ns09', 'جلوكوز 5% وملح 0.9%', 'dexsalt'),
  FluidDef('d5ns045', 'جلوكوز 5% وملح 0.45%', 'dexsalt'),
  FluidDef('d5ns018', 'جلوكوز 5% وملح 0.18%', 'dexsalt'),
  FluidDef('d43ns018', 'جلوكوز 4.3% وملح 0.18%', 'dexsalt'),
  FluidDef('d10ns09', 'جلوكوز 10% وملح 0.9%', 'dexsalt'),
  FluidDef('d10ns018', 'جلوكوز 10% وملح 0.18%', 'dexsalt'),
  FluidDef('d33ns03', 'جلوكوز 3.3% وملح 0.3%', 'dexsalt'),
  // ── جلوكوز + بوتاسيوم ──
  FluidDef('d5k02', 'جلوكوز 5% وبوتاسيوم كلوريد 0.2%', 'dexk'),
  FluidDef('d5k03', 'جلوكوز 5% وبوتاسيوم كلوريد 0.3%', 'dexk'),
  // ── ملح + بوتاسيوم ──
  FluidDef('ns09k03', 'ملح 0.9% وبوتاسيوم كلوريد 0.3%', 'saltk'),
  FluidDef('kcl15', 'بوتاسيوم كلوريد 15% مركز (أمبول للتخفيف داخل المحاليل)', 'saltk'),
  // ── مركبة ──
  FluidDef('neomaint', 'نيومينت (Neomaint): جلوكوز + ملح + بوتاسيوم', 'combo'),
  FluidDef('rawdament', 'راودامنت (Rawdament): جلوكوز + ملح + بوتاسيوم', 'combo'),
  FluidDef('metahydrial', 'ميتاهيدريال (Metahydrial): جلوكوز + ملح + بوتاسيوم + سترات الصوديوم', 'combo'),
  FluidDef('pansol', 'بانسول (Pansol): جلوكوز + ملح + بوتاسيوم + لاكتات الصوديوم', 'combo'),
  FluidDef('paediment', 'بيدمنت (Paediment): جلوكوز + ملح + بوتاسيوم + كالسيوم جلوكونات', 'combo'),
  FluidDef('sherimaint', 'شيريمينت (Sherimaint): جلوكوز + ملح + بوتاسيوم + كالسيوم جلوكونات', 'combo'),
  FluidDef('diarrhea', 'محلول الإسهال: جلوكوز + ملح + بوتاسيوم + أسيتات الصوديوم', 'combo'),
  // ── رينجر ──
  FluidDef('ringer', 'محلول رينجر', 'ringer', main: true),
  FluidDef('ringer_lactate', 'رينجر لاكتات (Hartmann)', 'ringer'),
  FluidDef('ringer_acetate', 'رينجر أسيتات', 'ringer'),
  FluidDef('d5ringer', 'جلوكوز 5% ورينجر', 'ringer'),
  // ── مانيتول ──
  FluidDef('mann10', 'مانيتول 10%', 'mannitol'),
  FluidDef('mann20', 'مانيتول 20%', 'mannitol'),
  // ── ألبيومين ──
  FluidDef('alb20', 'ألبيومين بشري 20%', 'albumin'),
  // ── بيكربونات ──
  FluidDef('bic5', 'بيكربونات صوديوم 5%', 'bicarb'),
  FluidDef('bic84', 'بيكربونات صوديوم 8.4%', 'bicarb'),
  // ── لاكتات ──
  FluidDef('lac185', 'لاكتات الصوديوم 1.85%', 'lactate'),
  FluidDef('lac16m', 'لاكتات الصوديوم 1/6 مولار', 'lactate'),
];

/// أسماء الألبيومين التجارية (للعرض فقط — الاختيار نفسه "ألبيومين بشري 20%")
const kAlbuminBrands = [
  'Albapure', 'Albunorm', 'Albutein', 'Buminate', 'Flexbumin', 'Plasbumin',
  'Vialebex', 'Human Albumin Kedrion', 'Human Albumin Octapharma',
];

/// الأربعة الواضحين (جلوكوز ملحي = مجموعة بتتفتح منها الأنواع)
List<FluidDef> get kMainFluids => kIvFluids.where((f) => f.main).toList();

List<FluidDef> fluidsOfGroup(String g) =>
    kIvFluids.where((f) => f.group == g).toList();

/// المجموعات اللي تحت "أخرى" (كل شيء ما عدا الأربعة الواضحين)
const kOtherGroups = [
  'salt', 'dex', 'dexk', 'saltk', 'combo', 'ringer',
  'mannitol', 'albumin', 'bicarb', 'lactate',
];

FluidDef? fluidById(String id) {
  for (final f in kIvFluids) {
    if (f.id == id) return f;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
//  المحاليل كأدوية في فحص التداخل/التوافق
//  المحرك (alert_engine.dart) بيشوف المحلول من محتواه: tokens بنفس أسماء المواد
//  في القاعدة (sodium / potassium / calcium / glucose ...) + شكل INF.
//  ده اللي بيخلي "سيفترياكسون + رينجر" و"بيدمنت" (فيه كالسيوم) يتنبّهوا.
// ─────────────────────────────────────────────────────────────────────────────
const _ringerBase = ['sodium', 'potassium', 'calcium'];

const _kFluidTokensById = <String, List<String>>{
  'kcl15': ['potassium'],
  'ns09k03': ['sodium', 'potassium'],
  'neomaint': ['glucose', 'sodium', 'potassium'],
  'rawdament': ['glucose', 'sodium', 'potassium'],
  'metahydrial': ['glucose', 'sodium', 'potassium', 'sodium citrate'],
  'pansol': ['glucose', 'sodium', 'potassium', 'sodium lactate'],
  'paediment': ['glucose', 'sodium', 'potassium', 'calcium gluconate'],
  'sherimaint': ['glucose', 'sodium', 'potassium', 'calcium gluconate'],
  'diarrhea': ['glucose', 'sodium', 'potassium', 'sodium acetate'],
  'ringer': _ringerBase,
  'ringer_lactate': [..._ringerBase, 'sodium lactate'],
  'ringer_acetate': [..._ringerBase, 'sodium acetate'],
  'd5ringer': ['glucose', ..._ringerBase],
};

const _kFluidTokensByGroup = <String, List<String>>{
  'salt': ['sodium'],
  'dex': ['glucose'],
  'dexsalt': ['glucose', 'sodium'],
  'dexk': ['glucose', 'potassium'],
  'saltk': ['sodium', 'potassium'],
  'mannitol': ['mannitol'],
  'albumin': ['albumin'],
  'bicarb': ['sodium bicarbonate'],
  'lactate': ['sodium lactate'],
};

/// المواد الموجودة في المحلول (lowercase) — فاضية لو غير معروف.
List<String> fluidTokensOf(FluidDef f) =>
    _kFluidTokensById[f.id] ?? _kFluidTokensByGroup[f.group] ?? const [];

/// المحلول كـ MedSnapshot (شكل INF) للدخول في فحص التداخل والتكرار.
/// isChronic=true عشان ما يتفحصش له مؤشر علاجي ولا جرعة.
MedSnapshot fluidSnapshot(FluidDef f, {int id = 5000}) {
  final t = fluidTokensOf(f);
  return MedSnapshot(
    drugId: id,
    brandName: f.name,
    genericName: t.join(' + '),
    genericTokens: t,
    strengthRaw: '',
    form: 'INF',
    frequency: '',
    isChronic: true,
  );
}

/// الأمبول/الفيال المضاف على المحلول كـ MedSnapshot (نفس منطق patient_file_screen
/// القديم: isChronic=true، بدون جرعة يومية).
MedSnapshot additiveSnapshot(MedicationModel m, int id) => MedSnapshot(
      drugId: id,
      brandName: m.brandName,
      genericName: m.genericName,
      rxcui: m.rxcui,
      genericTokens: m.genericTokens,
      strengthRaw: m.strength,
      form: m.form,
      frequency: m.frequency,
      isChronic: true,
    );

// ─────────────────────────────────────────────────────────────────────────────
//  هل الأمبول/الفيال مناسب للحقن الوريدي؟  (null = مناسب أو غير معروف)
//  ⚠️ القاعدة المحلية مفيهاش عمود "طريقة الإعطاء"، فالفحص مبني على:
//   (أ) قايمة مواد فعالة معروفة إنها IM/SC فقط  (ب) كلمات في الاسم التجاري
//   (IM / SC / DEPOT / PEN / PFS). لو ضفت عمود route للقاعدة بدّل الدالة دي.
// ─────────────────────────────────────────────────────────────────────────────
const _kNotIvTokens = <String, String>{
  'penicillin g benzathine': 'IM فقط',
  'benzathine penicillin': 'IM فقط',
  'benzathine benzylpenicillin': 'IM فقط',
  'penicillin g procaine': 'IM فقط',
  'diclofenac': 'IM فقط (الوريدي غير معتمد في معظم التحضيرات)',
  'cyanocobalamin': 'IM / SC فقط',
  'hydroxocobalamin': 'IM فقط',
  'enoxaparin': 'SC فقط',
  'nadroparin': 'SC فقط',
  'dalteparin': 'SC فقط',
  'tinzaparin': 'SC فقط',
  'fondaparinux': 'SC فقط',
  'medroxyprogesterone': 'IM / SC فقط',
  'testosterone': 'IM فقط',
  'estradiol valerate': 'IM فقط',
  'haloperidol decanoate': 'IM فقط',
  'fluphenazine decanoate': 'IM فقط',
  'liraglutide': 'SC فقط',
  'semaglutide': 'SC فقط',
  'teriparatide': 'SC فقط',
  'glatiramer': 'SC فقط',
  'adalimumab': 'SC فقط',
  'etanercept': 'SC فقط',
  'pegfilgrastim': 'SC فقط',
  'interferon': 'SC / IM فقط',
  'cholecalciferol': 'IM فقط',
  'promethazine': 'IM (الوريدي خطر على الوريد)',
};

final RegExp _reNotIvName = RegExp(
    r'(\bI\.?M\.?\b|\bS\.?C\.?\b|\bDEPOT\b|\bPENS?\b|\bPFS\b)',
    caseSensitive: false);

final RegExp _reIvName = RegExp(r'(\bI\.?\s?V\.?\b|\bINTRAVENOUS\b|\bIVP\b|\bIV\s*INF)',
    caseSensitive: false);

String? ivRouteWarning({
  required String brandName,
  required String genericName,
  required List<String> tokens,
}) {
  // لو الاسم نفسه مكتوب فيه إنه وريدي (IV / I.V. / INTRAVENOUS / IM OR IV) → مفيش تحذير
  if (_reIvName.hasMatch(brandName)) return null;
  final hay = <String>{...tokens.map((t) => t.toLowerCase()), genericName.toLowerCase()};
  for (final e in _kNotIvTokens.entries) {
    if (hay.any((h) => h.contains(e.key))) {
      return '$brandName ($genericName) غالبًا ${e.value} — غير مخصص للحقن الوريدي.';
    }
  }
  if (_reNotIvName.hasMatch(brandName)) {
    return '$brandName يبدو من الاسم إنه IM أو SC فقط — تأكد إنه مناسب للحقن الوريدي.';
  }
  return null;
}
