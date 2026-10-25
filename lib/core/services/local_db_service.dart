import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  MODELS  (زي ما هي — ماتغيرتش)
// ─────────────────────────────────────────────────────────────────────────────
class DrugSearchResult {
  final int id;
  final String brandName,
      tradeName,
      genericName,
      normalizedGenerics,
      strength,
      form;
  final int? rxcui;
  const DrugSearchResult({
    required this.id,
    required this.brandName,
    this.tradeName = '',
    required this.genericName,
    this.normalizedGenerics = '',
    required this.strength,
    required this.form,
    this.rxcui,
  });
  String get displayName => '$brandName $strength';

  /// أسماء المواد الفعالة (lowercase) — من normalized_generics المفصولة بـ "|"
  List<String> get genericTokens => normalizedGenerics
      .split('|')
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toList();
}

// ⚠️ الجدول الحقيقي drug_interactions بيخزن drug_a_name/drug_b_name كنص
// مباشر (مفيش rxcui_a/rxcui_b رقمي، ومفيش عمود management). المطابقة بقت
// بالاسم النصي للمادة الفعالة، وdrugAName/drugBName هنا بيرجعوا اسم
// الدواء (brand) المطابق فعليًا عند المريض، مش اسم المادة الفعالة الخام.
class DrugInteractionResult {
  final String drugAName, drugBName, severity, description;
  const DrugInteractionResult({
    required this.drugAName,
    required this.drugBName,
    required this.severity,
    required this.description,
  });
}

class HerbInteractionResult {
  final String herbName, drugName, severity, description;
  const HerbInteractionResult({
    required this.herbName,
    required this.drugName,
    required this.severity,
    required this.description,
  });
}

// ⚠️ diagnosis_drug_indications الحقيقي: rxcui TEXT + drug_name TEXT مباشر،
// والقيم الرقمية REAL مش TEXT. الأعمدة max_daily_dose/max_dose_unit جداد.
class DoseInfo {
  final String? rxcui;
  final double? adultDoseMin, adultDoseMax, adultFreqPerDay, adultMaxDaily;
  final String? adultUnit;
  final double? elderlyDoseMin, elderlyDoseMax;
  final String? elderlyUnit;
  final double? pedDosePerKgMin, pedDosePerKgMax, pedMaxDaily;
  final String? pedUnit;
  final double? neoDosePerKg;
  final String? neoUnit;
  final String? renalAdjustment, hepaticAdjustment;
  const DoseInfo({
    this.rxcui,
    this.adultDoseMin,
    this.adultDoseMax,
    this.adultUnit,
    this.adultFreqPerDay,
    this.adultMaxDaily,
    this.elderlyDoseMin,
    this.elderlyDoseMax,
    this.elderlyUnit,
    this.pedDosePerKgMin,
    this.pedDosePerKgMax,
    this.pedUnit,
    this.pedMaxDaily,
    this.neoDosePerKg,
    this.neoUnit,
    this.renalAdjustment,
    this.hepaticAdjustment,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  حدود الجرعات على مستوى المادة الفعالة (generic_dose_limits — DB v1.0.5)
//  مستقلة عن التشخيص (عكس DoseInfo اللي محتاج diagnosisIds). الأرقام الأساسية في
//  generic_dose_limits والأرقام البديلة لكل مصدر في generic_dose_limit_alt.
//  special_flag: indication_dependent | contraindicated_ped | age_band_not_linear |
//  monitored_levels | ul_supplement | topical_or_local | weekly_not_daily |
//  as_needed_not_chronic
// ─────────────────────────────────────────────────────────────────────────────
class DoseLimitRow {
  final String ingredient;
  final double? adultMaxDailyMg; // mg/يوم (للـ UL: الحد الأعلى الآمن)
  final double? pedMaxMgPerKgDay; // mg/kg/يوم
  final String? specialFlag, notes, source, pedNote, flagSeverity;
  final double? pedMinAgeYears; // contraindicated_ped فقط
  final bool verified; // 1 = مفيش خلاف بين المصادر (مش مراجعة صيدلي بشري)
  const DoseLimitRow({
    required this.ingredient,
    this.adultMaxDailyMg,
    this.pedMaxMgPerKgDay,
    this.specialFlag,
    this.notes,
    this.source,
    this.pedNote,
    this.flagSeverity,
    this.pedMinAgeYears,
    this.verified = false,
  });
}

class DoseLimitAlt {
  final String ingredient, sourceName;
  final String? sourceUrl, note;
  final double? adultMaxDailyMg, pedMaxMgPerKgDay;
  const DoseLimitAlt({
    required this.ingredient,
    required this.sourceName,
    this.sourceUrl,
    this.adultMaxDailyMg,
    this.pedMaxMgPerKgDay,
    this.note,
  });
}

double? _minOfNullable(Iterable<double?> xs) {
  double? m;
  for (final x in xs) {
    if (x != null && (m == null || x < m)) m = x;
  }
  return m;
}

/// كل صفوف الحدود المطابقة لدواء واحد (أكتر من صف لو للمادة أكتر من اسم، زي
/// acetaminophen/paracetamol) + الأرقام البديلة. لو الصفوف اتعارضت بنختار الأقل (الأحوط).
class DoseLimitInfo {
  final List<DoseLimitRow> rows;
  final List<DoseLimitAlt> alts;
  const DoseLimitInfo(this.rows, this.alts);

  /// مفتاح تجميع: نفس المادة في أكتر من دواء → الجرعة اليومية تتجمّع
  String get key => (rows.map((r) => r.ingredient).toList()..sort()).join('|');

  double? get adultMaxDailyMg =>
      _minOfNullable(rows.map((r) => r.adultMaxDailyMg));
  double? get pedMaxMgPerKgDay =>
      _minOfNullable(rows.map((r) => r.pedMaxMgPerKgDay));

  /// الصف صاحب السقف الأساسي (أو أول صف لو مفيش سقف)
  DoseLimitRow get primary {
    final cap = adultMaxDailyMg;
    return rows.firstWhere((r) => cap != null && r.adultMaxDailyMg == cap,
        orElse: () => rows.first);
  }

  bool get hasUl => rows.any((r) => r.specialFlag == 'ul_supplement');
  bool hasFlag(String f) => rows.any((r) => r.specialFlag == f);

  /// هل في أي مصدر (أساسي/بديل) سقف أطفال بالكيلو؟
  bool get hasPedPerKg =>
      pedMaxMgPerKgDay != null || alts.any((a) => a.pedMaxMgPerKgDay != null);
}

// ⚠️ beers_criteria الحقيقي مفيهوش rxcui — بيخزن drug_name/drug_lower مباشر
class BeersCriteriaResult {
  final String drugName;
  final String? category;
  final String rationale;
  final String? alternative;
  const BeersCriteriaResult({
    required this.drugName,
    this.category,
    required this.rationale,
    this.alternative,
  });
}

// نتيجة فحص المؤشر العلاجي (1.1)
//  official  = للدواء مؤشر موثّق لواحد من تشخيصات/أعراض المريض   → مفيش تنبيه
//  offLabel  = مؤشر شائع/غير رسمي (source = manual_offlabel)      → تنبيه info
//  notListed = الدواء والتشخيص كلاهما ليهم بيانات بس مفيش ربط      → تنبيه info
//  unknown   = مفيش بيانات كفاية نحكم (دواء/تشخيص مالوش بيانات)    → مفيش تنبيه
enum IndicationStatus { official, offLabel, notListed, unknown }

// الأدوية الموثّقة لتشخيص معيّن (للعرض في تنبيه 1.1)
class DiagnosisDrugs {
  final String diagnosis;
  final List<String> drugs; // المعروضة (محدودة)
  final int total; // الإجمالي في القاعدة
  const DiagnosisDrugs(this.diagnosis, this.drugs, this.total);
}

class IndicationResult {
  final IndicationStatus status;
  final String? note;
  const IndicationResult(this.status, [this.note]);
}

// ─────────────────────────────────────────────────────────────────────────────
//  LABS (DB v1.0.6) — lab_tests / lab_reference_ranges / diagnosis_lab_monitoring
// ─────────────────────────────────────────────────────────────────────────────
class LabTest {
  final int id;
  final String code, name;
  final String? abbreviation, panel, specimen, noteAr;
  final String unit;
  final double? criticalLow, criticalHigh;
  final String basis; // absolute | per_kg | formula
  const LabTest({
    required this.id,
    required this.code,
    required this.name,
    this.abbreviation,
    this.panel,
    this.specimen,
    this.noteAr,
    this.unit = '',
    this.criticalLow,
    this.criticalHigh,
    this.basis = 'absolute',
  });

  /// تحاليل نوعية (زرع/سمير/مصل...) — بتتسجل "طبيعي/غير طبيعي" مش رقم
  bool get isQualitative =>
      const {'qualitative', 'morphology', 'titer'}.contains(unit);

  String get shortName =>
      (abbreviation != null && abbreviation!.isNotEmpty) ? abbreviation! : name;
}

int labPriorityRank(String p) => switch (p) {
      'essential' => 0,
      'important' => 1,
      _ => 2,
    };

/// تحليل مقترح لمجموعة تشخيصات المريض (مدموج: لو التحليل مطلوب لأكتر من تشخيص
/// بناخد أعلى أولوية ونجمع الأسباب والأهداف).
class RecommendedLab {
  final LabTest lab;
  String priority; // essential | important | optional
  String frequency;
  final List<String> rationales = [];
  final List<String> targets = [];
  final List<String> diagnoses = [];
  final List<String> drugs = []; // الأدوية (brand) اللي طالبة التحليل
  RecommendedLab(this.lab, this.priority, this.frequency);
  int get rank => labPriorityRank(priority);
}

class LabRange {
  final double? low, high;
  final String? note;
  final String population;
  final bool sexAssumed; // جنس المريض مش مسجّل → المدى بيشمل الذكر والأنثى
  const LabRange({
    this.low,
    this.high,
    this.note,
    this.population = 'any',
    this.sexAssumed = false,
  });

  bool get isNumeric => low != null || high != null;

  String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  String text(String unit) {
    final u = unit.isEmpty ? '' : ' $unit';
    if (low != null && high != null) return '${_n(low!)} – ${_n(high!)}$u';
    if (high != null) return '≤ ${_n(high!)}$u';
    if (low != null) return '≥ ${_n(low!)}$u';
    return '—';
  }
}

enum LabStatus { normal, low, high, criticalLow, criticalHigh, unknown }

/// تقييم قيمة رقمية: الحرج الأول (من lab_tests)، وبعدين المدى المرجعي.
LabStatus evaluateLabValue(LabTest lab, LabRange? range, double v) {
  if (lab.criticalLow != null && v < lab.criticalLow!) {
    return LabStatus.criticalLow;
  }
  if (lab.criticalHigh != null && v > lab.criticalHigh!) {
    return LabStatus.criticalHigh;
  }
  if (range == null || !range.isNumeric) return LabStatus.unknown;
  if (range.low != null && v < range.low!) return LabStatus.low;
  if (range.high != null && v > range.high!) return LabStatus.high;
  return LabStatus.normal;
}

/// اختيار صف النسبة الطبيعية المناسب لسن/جنس/حمل المريض من صفوف lab_reference_ranges.
///  • الأضيق عمرياً أولاً (مسنّ > بالغ، رضيع > طفل...)، وبعدين الأخص بالجنس.
///  • الحمل بيتخطى لو المريضة مش حامل (وبيتفضّل لو حامل).
///  • الجنس مش معروف → بنوسّع المدى ليشمل الجنسين (sexAssumed).
///  • سن 12-17 ومفيش صف مناسب → بنرجع لمدى البالغين.
/// (السن في التطبيق بالسنين الصحيحة: 0 = حديث ولادة)
LabRange? pickLabRange(
  List<Map<String, Object?>> rows, {
  required int age,
  String? sex, // 'M' | 'F' | null
  bool isPregnant = false,
}) {
  final a = age.toDouble();
  double mn(Map<String, Object?> r) =>
      (r['age_min_years'] as num?)?.toDouble() ?? 0;
  double mx(Map<String, Object?> r) =>
      (r['age_max_years'] as num?)?.toDouble() ?? 120;
  bool inAge(Map<String, Object?> r) =>
      a >= mn(r) && (a < mx(r) || mx(r) >= 120);
  bool sexOk(Map<String, Object?> r) {
    final s = (r['sex'] as String?) ?? 'any';
    return sex == null || s == 'any' || s == sex;
  }

  bool isPreg(Map<String, Object?> r) => r['population'] == 'pregnancy';

  var cands = <Map<String, Object?>>[];
  if (isPregnant && sex != 'M') {
    cands = rows.where((r) => isPreg(r) && inAge(r)).toList();
  }
  if (cands.isEmpty) {
    cands = rows.where((r) => !isPreg(r) && inAge(r) && sexOk(r)).toList();
  }
  if (cands.isEmpty && age >= 12) {
    cands = rows.where((r) => !isPreg(r) && mn(r) >= 18 && sexOk(r)).toList();
  }
  if (cands.isEmpty) return null;

  // الأضيق عمرياً
  double span(Map<String, Object?> r) => mx(r) - mn(r);
  final minSpan = cands.map(span).reduce((x, y) => x < y ? x : y);
  cands = cands.where((r) => (span(r) - minSpan).abs() < 1e-9).toList();

  // الأخص بالجنس
  if (sex != null) {
    final exact = cands.where((r) => r['sex'] == sex).toList();
    if (exact.isNotEmpty) cands = exact;
  }

  double? lowOf(Map<String, Object?> r) => (r['low'] as num?)?.toDouble();
  double? highOf(Map<String, Object?> r) => (r['high'] as num?)?.toDouble();
  double? mergeLow = lowOf(cands.first);
  double? mergeHigh = highOf(cands.first);
  for (final r in cands.skip(1)) {
    final l = lowOf(r), h = highOf(r);
    mergeLow =
        (mergeLow == null || l == null) ? null : (l < mergeLow ? l : mergeLow);
    mergeHigh = (mergeHigh == null || h == null)
        ? null
        : (h > mergeHigh ? h : mergeHigh);
  }
  final sexes = cands.map((r) => (r['sex'] as String?) ?? 'any').toSet();
  return LabRange(
    low: mergeLow,
    high: mergeHigh,
    note: cands
        .map((r) => r['note'] as String?)
        .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => null),
    population: (cands.first['population'] as String?) ?? 'any',
    sexAssumed: sex == null && (sexes.contains('M') || sexes.contains('F')),
  );
}


// ─────────────────────────────────────────────────────────────────────────────
//  DDI v2 / عائلات الأدوية (DB v1.0.7) — drug_groups / drug_families /
//  drug_classes / ddi_rules. لو القاعدة أقدم من 1.0.7 كل الدوال بترجع فاضي.
//  مفاتيح القواعد: اسم مادة فعالة | 'class:<family>' | 'iv:<virtual>'
// ─────────────────────────────────────────────────────────────────────────────
class FamilyMembership {
  final String ingredient, family, familyAr, group, groupAr;
  final String dupSeverity; // none | info | minor | moderate | major
  final String routeScope; // any | oral
  final bool isBroad, soleOnly, groupDup;
  final double? doseGtMg; // العضوية بتتحسب بس لو الجرعة اليومية أكبر منه
  final String? dupNote;
  const FamilyMembership({
    required this.ingredient,
    required this.family,
    required this.familyAr,
    required this.group,
    required this.groupAr,
    required this.dupSeverity,
    required this.routeScope,
    required this.isBroad,
    required this.soleOnly,
    required this.groupDup,
    this.doseGtMg,
    this.dupNote,
  });
}

class DdiRuleRow {
  final int id;
  final String aKey, bKey, severity, alertType, effect;
  final String? management, neonateNote, source, sourceUrl;
  final bool verified;
  const DdiRuleRow({
    required this.id,
    required this.aKey,
    required this.bKey,
    required this.severity,
    required this.alertType,
    required this.effect,
    this.management,
    this.neonateNote,
    this.source,
    this.sourceUrl,
    this.verified = false,
  });
}

/// canon = الاسم الموحّد بعد دمج المرادفات (paracetamol↔acetaminophen)،
/// known = مادة دوائية معروفة في القاعدة (مش مكوّن تجميلي/عشبي).
class TokenInfo {
  final String canon;
  final bool known;
  const TokenInfo(this.canon, this.known);
}

// تمثيل مبسّط لدواء المريض لأغراض المطابقة النصية (تداخلات/حساسية/Beers) —
// label هو الاسم اللي هيتعرض في التنبيه، وgenericTokens أسماء المواد
// الفعالة (lowercase) بتاعته.
class MedTokens {
  final String label;
  final List<String> genericTokens;
  const MedTokens({required this.label, required this.genericTokens});
}

// ─────────────────────────────────────────────────────────────────────────────
//  LOCAL DB SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class LocalDbService {
  LocalDbService._();
  static final instance = LocalDbService._();

  Database? _db;

  static const _dbFileName = 'cp_app_medical.db';
  static const _dbVersion = '1.0.7';
  static const _dbUrl =
      'https://github.com/Hiha60/clinical-pharmacy-db/releases/download/db-v1.0.7/cp_app_medical.db';

  // callback لعرض progress في شاشة الـ splash
  void Function(double progress, String status)? onProgress;

  // ── Init ─────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_db != null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = join(appDir.path, _dbFileName);

    if (Platform.isAndroid) {
      await _initAndroid(dbPath);
    } else {
      await _initDesktop(dbPath);
    }

    _db = await openDatabase(dbPath, readOnly: true);
  }

  // ── Android: تحميل من GitHub ─────────────────────────────────────────
  Future<void> _initAndroid(String dbPath) async {
    final prefs = await SharedPreferences.getInstance();
    final savedVer = prefs.getString('db_version') ?? '';
    final fileExists = File(dbPath).existsSync();

    if (!fileExists || savedVer != _dbVersion) {
      try {
        onProgress?.call(0, 'جاري تحميل قاعدة البيانات الطبية...');
        await _downloadDb(dbPath);
        await prefs.setString('db_version', _dbVersion);
      } catch (e) {
        // أول مرة ومفيش نسخة قديمة → لازم نرمي الخطأ
        if (!fileExists) rethrow;
        debugPrint('⚠️ فشل تحديث الـ DB، هنكمل بالنسخة الحالية: $e');
      }
    }
  }

  // ── Android: تنفيذ التحميل ───────────────────────────────────────────
  Future<void> _downloadDb(String destPath) async {
    final client = http.Client();
    final tmp = File('$destPath.part');
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(_dbUrl)))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception(
            'فشل تحميل قاعدة البيانات — كود: ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      var received = 0;

      if (tmp.existsSync()) await tmp.delete();
      final sink = tmp.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final tot = (total / 1024 / 1024).toStringAsFixed(1);
            onProgress?.call(received / total, 'تحميل... $mb / $tot MB');
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      // تأكد إن الملف اتحمّل كامل قبل ما يستبدل القديم
      if (total > 0 && await tmp.length() != total) {
        throw Exception('الملف المحمّل غير مكتمل');
      }

      final dest = File(destPath);
      if (dest.existsSync()) await dest.delete();
      await tmp.rename(destPath);
    } catch (e) {
      if (tmp.existsSync()) await tmp.delete();
      rethrow;
    } finally {
      client.close();
    }
  }

  // ── Windows / Desktop: نسخ من الـ assets مع فحص الـ version ────────
  Future<void> _initDesktop(String dbPath) async {
    final prefs = await SharedPreferences.getInstance();
    final savedVer = prefs.getString('db_version') ?? '';
    final fileExists = File(dbPath).existsSync();

    if (!fileExists || savedVer != _dbVersion) {
      onProgress?.call(0, 'جاري تحديث قاعدة البيانات...');
      final data = await rootBundle.load('assets/databases/$_dbFileName');
      final bytes = data.buffer.asUint8List();
      await File(dbPath).writeAsBytes(bytes, flush: true);
      await prefs.setString('db_version', _dbVersion);
      onProgress?.call(1, 'جاهز');
    }
  }

  // ── استبدال الـ DB عند التحديث ────────────────────────────────────────
  Future<void> replaceDatabase(List<int> newDbBytes) async {
    await _db?.close();
    _db = null;
    _indHasNote = null;
    _doseLimitsOk = null;
    _labsOk = null;
    _drugLabRows = null;
    _resetDdiCaches();
    final appDir = await getApplicationDocumentsDirectory();
    final dbPath = join(appDir.path, _dbFileName);
    await File(dbPath).writeAsBytes(newDbBytes, flush: true);
    _db = await openDatabase(dbPath, readOnly: true);
  }

  Database get _database {
    assert(_db != null, 'LocalDbService.init() لم يُستدعَ بعد');
    return _db!;
  }

  // ── Drug Search ───────────────────────────────────────────────────────
  // ⚠️ الـ schema الحقيقي لجدول drugs: id, brand_name, trade_name, strength,
  // dosage_form, generic_name, normalized_generics, company, country,
  // brand_lower, trade_lower — مفيش generic_id ولا name_lower.
  // rxcui بيرجع null هنا لحد ما نعيد تصميم منطق المطابقة بالاسم النصي
  // (الخطوة الجاية) — يعني فحوصات التداخل/الجرعة/الحساسية لسه معطلة.
  // ⚠️ البحث بيرجع صف واحد لكل اسم تجاري (trade_name) — يعني "AUGMENTIN"
  // هتظهر مرة واحدة حتى لو ليها ١٠ تركيزات/أشكال مختلفة في القاعدة.
  // أسماء تجارية مختلفة بتشترك في جزء من الاسم (زي AUGMENTIN و
  // AUGMENTIN DUO) بتفضل تظهر كل واحدة لوحدها لأنها فعليًا منتجات مختلفة.
  // الأصناف اللي فيها "(CANCELLED)" في الاسم مستبعدة خالص.
  // التجميع بيتم في الـ Dart (مش GROUP BY في SQL) عشان نضمن إن الصف
  // اللي بيترجع فعلاً هو أول صف اتقابل بعد الترتيب حسب الأولوية.
  Future<List<DrugSearchResult>> searchDrugs(String query) async {
    if (query.trim().length < 2) return [];
    final q = query.trim().toLowerCase();
    try {
      final rows = await _database.rawQuery('''
        SELECT id, brand_name, trade_name, strength, dosage_form, generic_name, normalized_generics
        FROM drugs
        WHERE (brand_lower LIKE ? OR trade_lower LIKE ?)
          AND brand_lower NOT LIKE '%cancelled%'
        ORDER BY
          CASE WHEN trade_lower LIKE ? THEN 0 ELSE 1 END,
          trade_name,
          strength
        LIMIT 300
      ''', ['%$q%', '%$q%', '$q%']);

      final seenTrade = <String>{};
      final result = <DrugSearchResult>[];
      for (final r in rows) {
        final trade = ((r['trade_name'] as String?) ?? '').trim();
        final key = trade.toLowerCase();
        if (key.isEmpty || !seenTrade.add(key)) continue;

        result.add(DrugSearchResult(
          id: r['id'] as int,
          brandName: trade, // اسم البراند بس — مش الاسم الكامل بالتركيز
          tradeName: trade,
          genericName: (r['generic_name'] as String?) ?? '',
          normalizedGenerics: (r['normalized_generics'] as String?) ?? '',
          strength: '',
          form: '',
          rxcui: null,
        ));
        if (result.length >= 20) break;
      }
      return result;
    } catch (e, st) {
      debugPrint('❌ searchDrugs error: $e\n$st');
      return [];
    }
  }

  /// جيب كل التركيزات/الأشكال المتاحة لنفس المنتج التجاري (trade_name)
  /// (بدون الأصناف الملغاة "(CANCELLED)")
  Future<List<DrugSearchResult>> getStrengthsForBrand(String tradeName) async {
    if (tradeName.trim().isEmpty) return [];
    final t = tradeName.trim().toLowerCase();
    try {
      final rows = await _database.rawQuery('''
        SELECT id, brand_name, trade_name, strength, dosage_form, generic_name, normalized_generics
        FROM drugs
        WHERE trade_lower = ?
          AND brand_lower NOT LIKE '%cancelled%'
        ORDER BY strength, dosage_form
      ''', [t]);

      return rows
          .map((r) => DrugSearchResult(
                id: r['id'] as int,
                brandName: r['brand_name'] as String,
                tradeName: (r['trade_name'] as String?) ?? '',
                genericName: (r['generic_name'] as String?) ?? '',
                normalizedGenerics: (r['normalized_generics'] as String?) ?? '',
                strength: (r['strength'] as String?) ?? '',
                form: (r['dosage_form'] as String?) ?? '',
                rxcui: null,
              ))
          .toList();
    } catch (e, st) {
      debugPrint('❌ getStrengthsForBrand error: $e\n$st');
      return [];
    }
  }

  // ── أمبولات/فيالات فقط (للإضافة على المحاليل الوريدية) ───────────────────
  static const _parenteralFilter =
      "AND (UPPER(dosage_form) LIKE '%AMP%' OR UPPER(dosage_form) LIKE '%VIAL%')";

  Future<List<DrugSearchResult>> searchParenteralDrugs(String query) async {
    if (query.trim().length < 2) return [];
    final q = query.trim().toLowerCase();
    try {
      final rows = await _database.rawQuery('''
        SELECT id, brand_name, trade_name, strength, dosage_form, generic_name, normalized_generics
        FROM drugs
        WHERE (brand_lower LIKE ? OR trade_lower LIKE ?)
          AND brand_lower NOT LIKE '%cancelled%'
          $_parenteralFilter
        ORDER BY
          CASE WHEN trade_lower LIKE ? THEN 0 ELSE 1 END,
          trade_name,
          strength
        LIMIT 300
      ''', ['%$q%', '%$q%', '$q%']);

      final seenTrade = <String>{};
      final result = <DrugSearchResult>[];
      for (final r in rows) {
        final trade = ((r['trade_name'] as String?) ?? '').trim();
        final key = trade.toLowerCase();
        if (key.isEmpty || !seenTrade.add(key)) continue;
        result.add(DrugSearchResult(
          id: r['id'] as int,
          brandName: trade,
          tradeName: trade,
          genericName: (r['generic_name'] as String?) ?? '',
          normalizedGenerics: (r['normalized_generics'] as String?) ?? '',
          strength: '',
          form: '',
          rxcui: null,
        ));
        if (result.length >= 20) break;
      }
      return result;
    } catch (e, st) {
      debugPrint('❌ searchParenteralDrugs error: $e\n$st');
      return [];
    }
  }

  /// أصناف (تركيز/شكل) المنتج التجاري — الأمبولات والفيالات فقط
  Future<List<DrugSearchResult>> getParenteralVariants(String tradeName) async {
    if (tradeName.trim().isEmpty) return [];
    final t = tradeName.trim().toLowerCase();
    try {
      final rows = await _database.rawQuery('''
        SELECT id, brand_name, trade_name, strength, dosage_form, generic_name, normalized_generics
        FROM drugs
        WHERE trade_lower = ?
          AND brand_lower NOT LIKE '%cancelled%'
          $_parenteralFilter
        ORDER BY strength, dosage_form
      ''', [t]);
      return rows
          .map((r) => DrugSearchResult(
                id: r['id'] as int,
                brandName: r['brand_name'] as String,
                tradeName: (r['trade_name'] as String?) ?? '',
                genericName: (r['generic_name'] as String?) ?? '',
                normalizedGenerics: (r['normalized_generics'] as String?) ?? '',
                strength: (r['strength'] as String?) ?? '',
                form: (r['dosage_form'] as String?) ?? '',
                rxcui: null,
              ))
          .toList();
    } catch (e, st) {
      debugPrint('❌ getParenteralVariants error: $e\n$st');
      return [];
    }
  }

  // ── Drug-Drug Interactions ─────────────────────────────────────────────
  // ⚠️ drug_interactions بيخزن drug_a_name/drug_b_name كنص مباشر (lowercase).
  // الـ SQL بيجيب كل صف فيه أي طرف من أدوية المريض، وبعدين الـ Dart بيتحقق
  // إن الطرفين كلاهما موجودَين فعلاً عند المريض قبل ما يضيف التنبيه.
  // ده بيضمن إن Warfarin + Aspirin يتعرف عليه بغض النظر عن ترتيبهم في الـ DB.
  Future<List<DrugInteractionResult>> checkDrugInteractions(
      List<MedTokens> meds) async {
    final rawTokens = <String>{};
    for (final m in meds) {
      rawTokens.addAll(m.genericTokens);
    }
    if (rawTokens.length < 2) return [];

    // ✅ إصلاح DDI: نوسّع الـ tokens بالمرادفات من جدول synonyms
    // مثال: 'acetylsalicylic acid' → نضيف 'aspirin' عشان يتطابق مع DB
    // ونحتفظ بخريطة synonym → original عشان نعرف إيه الـ med المقابل
    final tokenToMeds = <String, List<MedTokens>>{};
    for (final m in meds) {
      for (final t in m.genericTokens) {
        tokenToMeds.putIfAbsent(t, () => []).add(m);
      }
    }
    // جيب المرادفات
    if (rawTokens.isNotEmpty) {
      final sp = rawTokens.map((_) => '?').join(',');
      final synRows = await _database.rawQuery('''
        SELECT egypt_name, rxnav_name FROM synonyms
        WHERE lower(egypt_name) IN ($sp) OR lower(rxnav_name) IN ($sp)
      ''', [...rawTokens, ...rawTokens]);
      for (final r in synRows) {
        final eg = (r['egypt_name'] as String).toLowerCase().trim();
        final rx = (r['rxnav_name'] as String).toLowerCase().trim();
        // لو eg موجود عند المريض → أضف rx كـ alias يشير لنفس الـ meds
        if (tokenToMeds.containsKey(eg)) {
          tokenToMeds.putIfAbsent(rx, () => []).addAll(tokenToMeds[eg]!);
        }
        if (tokenToMeds.containsKey(rx)) {
          tokenToMeds.putIfAbsent(eg, () => []).addAll(tokenToMeds[rx]!);
        }
      }
    }
    final allTokens = tokenToMeds.keys.toSet();

    final p = allTokens.map((_) => '?').join(',');
    // جيب كل صف فيه أي طرف من أدوية المريض (بما فيها المرادفات)
    final rows = await _database.rawQuery('''
      SELECT drug_a_name, drug_b_name, severity, description
      FROM drug_interactions
      WHERE (lower(drug_a_name) IN ($p) OR lower(drug_b_name) IN ($p))
        AND severity != 'Unknown'
      ORDER BY CASE severity WHEN 'Major' THEN 0 WHEN 'Moderate' THEN 1 WHEN 'Minor' THEN 2 ELSE 3 END
    ''', [...allTokens, ...allTokens]);

    final results = <DrugInteractionResult>[];
    final seen = <String>{};
    for (final row in rows) {
      final a = (row['drug_a_name'] as String).toLowerCase().trim();
      final b = (row['drug_b_name'] as String).toLowerCase().trim();

      // ✅ استخدم tokenToMeds اللي بيشمل المرادفات — ده بيحل مشكلة
      // acetylsalicylic acid مش بيتطابق مع aspirin في جدول التداخلات
      final medsA = tokenToMeds[a] ?? [];
      final medsB = tokenToMeds[b] ?? [];

      // لو أحد الطرفين مش موجود عند المريض → تجاهل (لا تنبيه)
      if (medsA.isEmpty || medsB.isEmpty) continue;

      for (final ma in medsA) {
        for (final mb in medsB) {
          if (identical(ma, mb)) continue; // نفس الدواء (تركيبة مركّبة)
          // مفتاح الـ dedup بيشمل الاتجاهين (a↔b) عشان منكررش نفس التنبيه
          final keyFwd = '${row['severity']}|$a|$b|${ma.label}|${mb.label}';
          final keyRev = '${row['severity']}|$b|$a|${mb.label}|${ma.label}';
          if (seen.contains(keyFwd) || seen.contains(keyRev)) continue;
          seen.add(keyFwd);
          results.add(DrugInteractionResult(
            drugAName: ma.label,
            drugBName: mb.label,
            severity: (row['severity'] as String?) ?? 'Unknown',
            description: (row['description'] as String?) ?? '',
          ));
        }
      }
    }
    return results;
  }

  // ── Herb-Drug Interactions ─────────────────────────────────────────────
  // ⚠️ herb_interactions الحقيقي بيخزن drug_name/drug_lower مباشر (بدون
  // rxcui)، وherb_aliases مفيهوش is_primary — الاسم الأساسي في herbs.
  // ملحوظة: بيانات المريض حاليًا مفيهاش تتبّع للأعشاب في الفورم، فـ
  // herbNames هتكون فاضية دايمًا لحد ما تتضاف الميزة دي — الدالة جاهزة.
  Future<List<HerbInteractionResult>> checkHerbInteractions(
      List<MedTokens> meds,
      {List<String> herbNames = const []}) async {
    if (herbNames.isEmpty) return [];
    final allTokens = <String>{};
    for (final m in meds) {
      allTokens.addAll(m.genericTokens);
    }
    if (allTokens.isEmpty) return [];

    final herbLowers = herbNames.map((e) => e.trim().toLowerCase()).toSet();
    final hp = herbLowers.map((_) => '?').join(',');
    final herbRows = await _database.rawQuery('''
      SELECT DISTINCT h.id, h.canonical_name
      FROM herbs h
      LEFT JOIN herb_aliases ha ON ha.herb_id = h.id
      WHERE lower(h.canonical_name) IN ($hp) OR lower(ha.alias_lower) IN ($hp)
    ''', [...herbLowers, ...herbLowers]);
    if (herbRows.isEmpty) return [];
    final herbIds = herbRows.map((r) => r['id']).toList();
    final herbNameById = {
      for (final r in herbRows) r['id']: r['canonical_name'] as String
    };

    final dp = allTokens.map((_) => '?').join(',');
    final ip = herbIds.map((_) => '?').join(',');
    final rows = await _database.rawQuery('''
      SELECT herb_id, drug_name, severity, effect, mechanism
      FROM herb_interactions
      WHERE herb_id IN ($ip) AND lower(drug_lower) IN ($dp)
    ''', [...herbIds, ...allTokens]);

    return rows
        .map((r) => HerbInteractionResult(
              herbName: herbNameById[r['herb_id']] ?? '',
              drugName: r['drug_name'] as String,
              severity: (r['severity'] as String?) ?? 'Unknown',
              description: [r['effect'], r['mechanism']]
                  .where((e) => e != null && (e as String).isNotEmpty)
                  .join(' — '),
            ))
        .toList();
  }

  // ── Allergy Check ──────────────────────────────────────────────────────
  // ⚠️ مفيش drug_class/atc_code في generics الحقيقي، يعني مفيش تصنيف
  // عائلات أدوية (زي "كل البنسلينات") — التطابق هنا بالاسم الفعلي للمادة
  // الفعالة فقط + مرادفاتها من جدول synonyms + مطابقة جزئية احتياطية.
  Future<bool> checkAllergy({
    required List<String> genericTokens,
    required String fallbackText, // brand_name + generic_name للمطابقة الجزئية
    required List<String> allergenNames,
  }) async {
    if (allergenNames.isEmpty || genericTokens.isEmpty) return false;
    final allergenLowers = allergenNames
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (allergenLowers.isEmpty) return false;

    // ١. تطابق مباشر مع المادة الفعالة
    if (genericTokens.any(allergenLowers.contains)) return true;

    // ٢. تطابق عن طريق جدول المرادفات (في الاتجاهين)
    final p = allergenLowers.map((_) => '?').join(',');
    final synRows = await _database.rawQuery('''
      SELECT egypt_name, rxnav_name FROM synonyms
      WHERE lower(egypt_name) IN ($p) OR lower(rxnav_name) IN ($p)
    ''', [...allergenLowers, ...allergenLowers]);
    for (final r in synRows) {
      final eg = (r['egypt_name'] as String).toLowerCase();
      final rx = (r['rxnav_name'] as String).toLowerCase();
      if (genericTokens.contains(eg) || genericTokens.contains(rx)) return true;
    }

    // ٣. مطابقة جزئية احتياطية (نص التحسس موجود جوه اسم الدواء/المادة)
    final text = fallbackText.toLowerCase();
    for (final a in allergenLowers) {
      if (a.length >= 4 && text.contains(a)) return true;
    }
    return false;
  }

  // ── Dose Info ──────────────────────────────────────────────────────────
  // ⚠️ المطابقة بقت بـ drug_name النصي بدل rxcui رقمي. لسه معطّلة عمليًا
  // لأن diagnosisIds بتوصل فاضية دايمًا حاليًا (التشخيص بيتحفظ باسمه بس
  // من غير id في بيانات المريض) — شوف الملاحظة في alert_engine.dart.
  Future<DoseInfo?> getDoseInfo({
    required List<String> genericTokens,
    required List<int> diagnosisIds,
  }) async {
    if (diagnosisIds.isEmpty || genericTokens.isEmpty) return null;
    final dp = genericTokens.map((_) => '?').join(',');
    final ip = diagnosisIds.map((_) => '?').join(',');
    final rows = await _database.rawQuery('''
      SELECT * FROM diagnosis_drug_indications
      WHERE lower(drug_name) IN ($dp) AND diagnosis_id IN ($ip)
        AND (adult_dose_min IS NOT NULL
          OR ped_dose_per_kg_min IS NOT NULL
          OR neo_dose_per_kg IS NOT NULL)
      LIMIT 1
    ''', [...genericTokens, ...diagnosisIds]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    double? d(String k) => (r[k] as num?)?.toDouble();
    return DoseInfo(
      rxcui: r['rxcui'] as String?,
      adultDoseMin: d('adult_dose_min'),
      adultDoseMax: d('adult_dose_max'),
      adultUnit: r['adult_unit'] as String?,
      adultFreqPerDay: d('adult_freq_per_day'),
      adultMaxDaily: d('adult_max_daily'),
      elderlyDoseMin: d('elderly_dose_min'),
      elderlyDoseMax: d('elderly_dose_max'),
      elderlyUnit: r['elderly_unit'] as String?,
      pedDosePerKgMin: d('ped_dose_per_kg_min'),
      pedDosePerKgMax: d('ped_dose_per_kg_max'),
      pedUnit: r['ped_unit'] as String?,
      pedMaxDaily: d('ped_max_daily'),
      neoDosePerKg: d('neo_dose_per_kg'),
      neoUnit: r['neo_unit'] as String?,
      renalAdjustment: r['renal_adjustment'] as String?,
      hepaticAdjustment: r['hepatic_adjustment'] as String?,
    );
  }

  // ── Dose Limits (generic_dose_limits — DB v1.0.5) ─────────────────────────
  // مطابقة بالاسم النصي للمادة الفعالة (+ المرادفات من synonyms + جدول
  // generic_dose_limit_aliases للأسماء المختلفة بين ملف الجرعات وجدول drugs).
  // لو الـ DB قديمة (الجداول مش موجودة) بترجع null بدل ما تكسر.
  bool? _doseLimitsOk;
  Future<bool> _doseLimitsAvailable() async {
    if (_doseLimitsOk != null) return _doseLimitsOk!;
    try {
      final rows = await _database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
          "('generic_dose_limits', 'generic_dose_limit_aliases')");
      _doseLimitsOk = rows.length == 2;
    } catch (_) {
      _doseLimitsOk = false;
    }
    return _doseLimitsOk!;
  }

  Future<DoseLimitInfo?> getDoseLimits(List<String> genericTokens) async {
    if (genericTokens.isEmpty || !await _doseLimitsAvailable()) return null;
    try {
      final tokens = (await _expandWithSynonyms(genericTokens)).toList();
      if (tokens.isEmpty) return null;
      final p = tokens.map((_) => '?').join(',');
      final rows = await _database.rawQuery('''
        SELECT * FROM generic_dose_limits
        WHERE lower(ingredient) IN ($p)
           OR lower(ingredient) IN (
                SELECT lower(ingredient) FROM generic_dose_limit_aliases
                WHERE alias_lower IN ($p))
      ''', [...tokens, ...tokens]);
      if (rows.isEmpty) return null;

      double? d(Map<String, Object?> r, String k) => (r[k] as num?)?.toDouble();
      String? s(Map<String, Object?> r, String k) {
        final v = r[k] as String?;
        return (v == null || v.trim().isEmpty) ? null : v;
      }

      final limitRows = rows
          .map((r) => DoseLimitRow(
                ingredient: (r['ingredient'] as String).toLowerCase(),
                adultMaxDailyMg: d(r, 'adult_max_daily_mg'),
                pedMaxMgPerKgDay: d(r, 'ped_max_mg_per_kg_day'),
                specialFlag: s(r, 'special_flag'),
                notes: s(r, 'notes'),
                source: s(r, 'source'),
                pedNote: s(r, 'ped_note'),
                flagSeverity: s(r, 'flag_severity'),
                pedMinAgeYears: d(r, 'ped_min_age_years'),
                verified: ((r['verified'] as num?)?.toInt() ?? 0) == 1,
              ))
          .toList();

      // الأرقام البديلة لكل مصدر (بدون تكرار لو نفس المادة ليها أكتر من اسم)
      final alts = <DoseLimitAlt>[];
      try {
        final names = limitRows.map((r) => r.ingredient).toSet().toList();
        final ap = names.map((_) => '?').join(',');
        final altRows = await _database.rawQuery(
            'SELECT * FROM generic_dose_limit_alt WHERE lower(ingredient) IN ($ap)',
            names);
        final seen = <String>{};
        for (final r in altRows) {
          final a = DoseLimitAlt(
            ingredient: (r['ingredient'] as String).toLowerCase(),
            sourceName: (r['source_name'] as String?) ?? '',
            sourceUrl: s(r, 'source_url'),
            adultMaxDailyMg: d(r, 'adult_max_daily_mg'),
            pedMaxMgPerKgDay: d(r, 'ped_max_mg_per_kg_day'),
            note: s(r, 'note'),
          );
          final key =
              '${a.sourceName}|${a.adultMaxDailyMg}|${a.pedMaxMgPerKgDay}';
          if (seen.add(key)) alts.add(a);
        }
      } catch (_) {/* جدول alt اختياري */}

      return DoseLimitInfo(limitRows, alts);
    } catch (e, st) {
      debugPrint('❌ getDoseLimits error: $e\n$st');
      return null;
    }
  }

  // ── Indication Check (قديم — استخدم checkIndication) ────────────────────
  Future<bool> hasIndication({
    required List<String> genericTokens,
    required List<int> diagnosisIds,
  }) async {
    if (diagnosisIds.isEmpty) return true; // مفيش تشخيص → مش بنحكم
    if (genericTokens.isEmpty) return false;
    final dp = genericTokens.map((_) => '?').join(',');
    final ip = diagnosisIds.map((_) => '?').join(',');
    final rows = await _database.rawQuery('''
      SELECT COUNT(*) AS cnt FROM diagnosis_drug_indications
      WHERE lower(drug_name) IN ($dp) AND diagnosis_id IN ($ip)
    ''', [...genericTokens, ...diagnosisIds]);
    return (Sqflite.firstIntValue(rows) ?? 0) > 0;
  }

  // ── Diagnosis name → id ────────────────────────────────────────────────
  // تشخيصات المريض متخزنة كنصوص (أسماء) — هنا بنحوّلها لـ ids عشان فحوصات
  // المؤشر العلاجي والجرعة. بيدور بالاسم الأساسي وبالـ aliases كمان.
  Future<List<int>> resolveDiagnosisIds(List<String> names) async {
    final lowers = names
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (lowers.isEmpty) return [];
    final p = lowers.map((_) => '?').join(',');
    try {
      final rows = await _database.rawQuery('''
        SELECT id FROM diagnoses WHERE name_lower IN ($p)
        UNION
        SELECT dam.diagnosis_id AS id
        FROM diagnosis_aliases da
        JOIN diagnosis_alias_maps dam ON dam.alias_id = da.id
        WHERE da.alias_lower IN ($p)
      ''', [...lowers, ...lowers]);
      return rows.map((r) => r['id'] as int).toList();
    } catch (e, st) {
      debugPrint('❌ resolveDiagnosisIds error: $e\n$st');
      return [];
    }
  }

  /// الأعراض اللي ليها تشخيص بنفس الاسم بالظبط (Cough ↔ Cough, Fever ↔ Fever...)
  /// بنعتبر أدوية التشخيص ده مؤشر علاجي للعرض. (مش بنستخدم diagnosis_symptoms
  /// هنا لأنها بتربط "مرض يسبب عرض" — مش "دواء يعالج العرض".)
  Future<List<int>> diagnosisIdsForSymptoms(List<String> symptoms) async {
    final lowers = symptoms
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (lowers.isEmpty) return [];
    final p = lowers.map((_) => '?').join(',');
    try {
      final rows = await _database.rawQuery('''
        SELECT d.id AS id FROM diagnoses d
        JOIN symptoms s ON s.name_lower = d.name_lower
        WHERE s.name_lower IN ($p)
      ''', lowers);
      return rows.map((r) => r['id'] as int).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Synonyms expansion (paracetamol ↔ acetaminophen ...) ────────────────
  Future<Set<String>> _expandWithSynonyms(Iterable<String> tokens) async {
    final base = tokens
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (base.isEmpty) return base;
    final p = base.map((_) => '?').join(',');
    final rows = await _database.rawQuery('''
      SELECT egypt_name, rxnav_name FROM synonyms
      WHERE lower(egypt_name) IN ($p) OR lower(rxnav_name) IN ($p)
    ''', [...base, ...base]);
    final out = {...base};
    for (final r in rows) {
      out.add((r['egypt_name'] as String).toLowerCase().trim());
      out.add((r['rxnav_name'] as String).toLowerCase().trim());
    }
    return out;
  }

  // أقل عدد ربط (دواء↔تشخيص) لازم يكون للتشخيص عشان نحكم إن دواء "مش موجود"
  // له. تشخيص عنده ١–٢ دواء بس معناه إن القاعدة ناقصة، مش إن باقي الأدوية غلط.
  static const kMinDiagnosisCoverage = 3;

  bool? _indHasNote;
  Future<bool> _indicationsHaveNote() async {
    if (_indHasNote != null) return _indHasNote!;
    try {
      final cols = await _database
          .rawQuery('PRAGMA table_info(diagnosis_drug_indications)');
      _indHasNote = cols.any((c) => c['name'] == 'note');
    } catch (_) {
      _indHasNote = false;
    }
    return _indHasNote!;
  }

  // ── Indication Check (1.1) — النسخة الجديدة ──────────────────────────────
  // الحكم بـ "مالوش مؤشر" لازم يكون عن بيانات، مش عن غياب بيانات:
  //  • الدواء أو أي مكوّن فيه له صف مع أي تشخيص → official/offLabel
  //  • لو مفيش: نحكم notListed بس لو الدواء نفسه ليه مؤشرات في القاعدة
  //    ولو التشخيص عنده تغطية كافية — غير كده unknown (ما بنحذّرش).
  Future<IndicationResult> checkIndication({
    required List<String> genericTokens,
    required List<int> diagnosisIds,
  }) async {
    if (diagnosisIds.isEmpty || genericTokens.isEmpty) {
      return const IndicationResult(IndicationStatus.unknown);
    }
    try {
      final tokens = (await _expandWithSynonyms(genericTokens)).toList();
      final dp = tokens.map((_) => '?').join(',');
      final ip = diagnosisIds.map((_) => '?').join(',');
      final hasNote = await _indicationsHaveNote();

      final rows = await _database.rawQuery('''
        SELECT source, ${hasNote ? 'note' : 'NULL'} AS note
        FROM diagnosis_drug_indications
        WHERE lower(drug_name) IN ($dp) AND diagnosis_id IN ($ip)
      ''', [...tokens, ...diagnosisIds]);

      if (rows.isNotEmpty) {
        if (rows.any((r) => r['source'] != 'manual_offlabel')) {
          return const IndicationResult(IndicationStatus.official);
        }
        final note = rows.map((r) => r['note']).whereType<String>().firstOrNull;
        return IndicationResult(IndicationStatus.offLabel, note);
      }

      final drugCov = Sqflite.firstIntValue(await _database.rawQuery(
              'SELECT COUNT(*) FROM diagnosis_drug_indications '
              'WHERE lower(drug_name) IN ($dp)',
              tokens)) ??
          0;
      if (drugCov == 0) return const IndicationResult(IndicationStatus.unknown);

      final diagCov = Sqflite.firstIntValue(await _database.rawQuery(
              'SELECT COUNT(*) FROM diagnosis_drug_indications '
              'WHERE diagnosis_id IN ($ip)',
              diagnosisIds)) ??
          0;
      if (diagCov < kMinDiagnosisCoverage) {
        return const IndicationResult(IndicationStatus.unknown);
      }
      return const IndicationResult(IndicationStatus.notListed);
    } catch (e, st) {
      debugPrint('❌ checkIndication error: $e\n$st');
      return const IndicationResult(IndicationStatus.unknown);
    }
  }

  /// الأدوية الموثّقة (RxClass + manual، من غير off-label) لكل تشخيص من ids.
  /// المضاف يدوياً (manual) أولاً، وبعدين أبجدياً. بيتخطى التشخيصات اللي مالهاش
  /// بيانات، ويرجّع حد أقصى [maxDiagnoses] تشخيص و[perDiagnosis] دواء لكل واحد.
  Future<List<DiagnosisDrugs>> documentedDrugsForDiagnoses(
    List<int> diagnosisIds, {
    int perDiagnosis = 8,
    int maxDiagnoses = 3,
  }) async {
    final out = <DiagnosisDrugs>[];
    try {
      for (final id in diagnosisIds.toSet()) {
        if (out.length >= maxDiagnoses) break;
        final rows = await _database.rawQuery('''
          SELECT lower(i.drug_name) AS drug,
                 MAX(i.source = 'manual') AS curated,
                 d.name AS diagnosis
          FROM diagnosis_drug_indications i
          JOIN diagnoses d ON d.id = i.diagnosis_id
          WHERE i.diagnosis_id = ? AND i.source IS NOT 'manual_offlabel'
          GROUP BY lower(i.drug_name)
          ORDER BY curated DESC, drug
        ''', [id]);
        if (rows.isEmpty) continue;
        out.add(DiagnosisDrugs(
          rows.first['diagnosis'] as String,
          rows.take(perDiagnosis).map((r) => r['drug'] as String).toList(),
          rows.length,
        ));
      }
    } catch (e, st) {
      debugPrint('❌ documentedDrugsForDiagnoses error: $e\n$st');
    }
    return out;
  }

  // ── Beers Criteria ─────────────────────────────────────────────────────
  // ⚠️ beers_criteria الحقيقي: drug_name/drug_lower مباشر، مفيش rxcui
  Future<List<BeersCriteriaResult>> checkBeersCriteria(
      List<MedTokens> meds) async {
    // ✅ Set بيجمع الـ tokens الفريدة فقط — لو 'warfarin' موجود في
    // prescribed + chronic معاً، يتحسب مرة واحدة بس → Beers مش بيتكرر
    final allTokens = <String>{};
    for (final m in meds) {
      allTokens.addAll(m.genericTokens);
    }
    if (allTokens.isEmpty) return [];
    final p = allTokens.map((_) => '?').join(',');
    final rows = await _database.rawQuery('''
      SELECT DISTINCT drug_lower, drug_name, category, rationale, alternative
      FROM beers_criteria
      WHERE drug_lower IN ($p)
    ''', allTokens.toList());
    return rows
        .map((r) => BeersCriteriaResult(
              drugName: r['drug_name'] as String,
              category: r['category'] as String?,
              rationale: (r['rationale'] as String?) ?? '',
              alternative: r['alternative'] as String?,
            ))
        .toList();
  }

  // ── Labs (DB v1.0.6) ───────────────────────────────────────────────────
  // لو الـ DB قديمة (الجداول مش موجودة) كل الدوال بترجع فاضي بدل ما تكسر.
  bool? _labsOk;
  Future<bool> labsAvailable() async {
    if (_labsOk != null) return _labsOk!;
    try {
      final rows = await _database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
          "('lab_tests', 'lab_reference_ranges', 'diagnosis_lab_monitoring')");
      _labsOk = rows.length == 3;
    } catch (_) {
      _labsOk = false;
    }
    return _labsOk!;
  }

  LabTest _labFromRow(Map<String, Object?> r) => LabTest(
        id: r['id'] as int,
        code: r['code'] as String,
        name: r['name'] as String,
        abbreviation: r['abbreviation'] as String?,
        panel: r['panel'] as String?,
        specimen: r['specimen'] as String?,
        noteAr: r['note_ar'] as String?,
        unit: (r['unit'] as String?) ?? '',
        criticalLow: (r['critical_low'] as num?)?.toDouble(),
        criticalHigh: (r['critical_high'] as num?)?.toDouble(),
        basis: (r['basis'] as String?) ?? 'absolute',
      );

  /// التحاليل المطلوبة لتشخيصات المريض (مدموجة، الأساسي الأول).
  Future<List<RecommendedLab>> getRecommendedLabs(
      List<int> diagnosisIds) async {
    final ids = diagnosisIds.toSet().toList();
    if (ids.isEmpty || !await labsAvailable()) return [];
    try {
      final ip = ids.map((_) => '?').join(',');
      final rows = await _database.rawQuery('''
        SELECT l.id AS id, l.code AS code, l.name AS name,
               l.abbreviation AS abbreviation, l.panel AS panel,
               l.unit AS unit, l.specimen AS specimen, l.note_ar AS note_ar,
               l.critical_low AS critical_low, l.critical_high AS critical_high,
               l.basis AS basis,
               m.priority AS priority, m.frequency AS frequency,
               m.rationale AS rationale, m.target AS target,
               d.name AS diagnosis
        FROM diagnosis_lab_monitoring m
        JOIN lab_tests l ON l.id = m.lab_id
        JOIN diagnoses d ON d.id = m.diagnosis_id
        WHERE m.diagnosis_id IN ($ip)
      ''', ids);

      final byCode = <String, RecommendedLab>{};
      for (final r in rows) {
        final lab = _labFromRow(r);
        final pr = (r['priority'] as String?) ?? 'optional';
        final fr = (r['frequency'] as String?) ?? '';
        final rec =
            byCode.putIfAbsent(lab.code, () => RecommendedLab(lab, pr, fr));
        if (labPriorityRank(pr) < rec.rank) {
          rec.priority = pr;
          rec.frequency = fr;
        }
        void add(List<String> l, Object? v) {
          final s = (v as String?)?.trim();
          if (s != null && s.isNotEmpty && !l.contains(s)) l.add(s);
        }

        add(rec.rationales, r['rationale']);
        add(rec.targets, r['target']);
        add(rec.diagnoses, r['diagnosis']);
      }
      final out = byCode.values.toList()
        ..sort((a, b) {
          final c = a.rank.compareTo(b.rank);
          if (c != 0) return c;
          final p = (a.lab.panel ?? '').compareTo(b.lab.panel ?? '');
          return p != 0 ? p : a.lab.name.compareTo(b.lab.name);
        });
      return out;
    } catch (e, st) {
      debugPrint('❌ getRecommendedLabs error: $e\n$st');
      return [];
    }
  }

  // ── ربط الأدوية بالتحاليل (drug_lab_monitoring — DB v1.0.6+) ─────────────
  List<Map<String, Object?>>? _drugLabRows;
  Future<List<Map<String, Object?>>> _loadDrugLabRows() async {
    final cached = _drugLabRows;
    if (cached != null) return cached;
    var out = <Map<String, Object?>>[];
    try {
      if (await labsAvailable()) {
        final t = await _database
            .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' "
                "AND name = 'drug_lab_monitoring'");
        if (t.isNotEmpty) {
          out = await _database.rawQuery('''
            SELECT l.id AS id, l.code AS code, l.name AS name,
                   l.abbreviation AS abbreviation, l.panel AS panel,
                   l.unit AS unit, l.specimen AS specimen, l.note_ar AS note_ar,
                   l.critical_low AS critical_low, l.critical_high AS critical_high,
                   l.basis AS basis,
                   m.generic_token AS generic_token, m.priority AS priority,
                   m.frequency AS frequency, m.rationale AS rationale,
                   m.target AS target
            FROM drug_lab_monitoring m
            JOIN lab_tests l ON l.id = m.lab_id
          ''');
        }
      }
    } catch (e, st) {
      debugPrint('❌ _loadDrugLabRows error: $e\n$st');
    }
    _drugLabRows = out;
    return out;
  }

  /// التحاليل المقترحة من التشخيصات + أدوية المريض (موصوفة ومزمنة).
  /// نفس التحليل المطلوب من أكتر من مصدر بيتدمج: أعلى أولوية + تجميع الأسباب.
  Future<List<RecommendedLab>> getRecommendedLabsFor({
    required List<int> diagnosisIds,
    List<MedTokens> drugTokens = const [],
  }) async {
    final fromDx = await getRecommendedLabs(diagnosisIds);
    if (drugTokens.isEmpty) return fromDx;
    final rows = await _loadDrugLabRows();
    if (rows.isEmpty) return fromDx;

    final byToken = <String, List<Map<String, Object?>>>{};
    for (final r in rows) {
      byToken
          .putIfAbsent(
              ((r['generic_token'] as String?) ?? '').toLowerCase(), () => [])
          .add(r);
    }
    final byCode = {for (final r in fromDx) r.lab.code: r};
    void add(List<String> l, Object? v) {
      final s = (v as String?)?.trim();
      if (s != null && s.isNotEmpty && !l.contains(s)) l.add(s);
    }

    for (final med in drugTokens) {
      for (final tok in med.genericTokens) {
        for (final r in byToken[tok.toLowerCase()] ?? const []) {
          final lab = _labFromRow(r);
          final pr = (r['priority'] as String?) ?? 'optional';
          final fr = (r['frequency'] as String?) ?? '';
          final rec =
              byCode.putIfAbsent(lab.code, () => RecommendedLab(lab, pr, fr));
          if (labPriorityRank(pr) < rec.rank) {
            rec.priority = pr;
            rec.frequency = fr;
          }
          final ra = (r['rationale'] as String?)?.trim() ?? '';
          add(rec.rationales, ra.isEmpty ? null : '${med.label}: $ra');
          add(rec.targets, r['target']);
          add(rec.drugs, med.label);
        }
      }
    }
    return byCode.values.toList()
      ..sort((a, b) {
        final c = a.rank.compareTo(b.rank);
        if (c != 0) return c;
        final p = (a.lab.panel ?? '').compareTo(b.lab.panel ?? '');
        return p != 0 ? p : a.lab.name.compareTo(b.lab.name);
      });
  }

  Future<LabTest?> getLabByCode(String code) async {
    if (!await labsAvailable()) return null;
    try {
      final rows = await _database
          .rawQuery('SELECT * FROM lab_tests WHERE code = ? LIMIT 1', [code]);
      return rows.isEmpty ? null : _labFromRow(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// بحث في كل التحاليل (لإضافة تحليل مش مقترح)
  Future<List<LabTest>> searchLabs(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2 || !await labsAvailable()) return [];
    try {
      final rows = await _database.rawQuery('''
        SELECT * FROM lab_tests
        WHERE name_lower LIKE ? OR lower(abbreviation) LIKE ? OR lower(code) LIKE ?
        ORDER BY CASE WHEN name_lower LIKE ? THEN 0 ELSE 1 END, name
        LIMIT 15
      ''', ['%$q%', '%$q%', '%$q%', '$q%']);
      return rows.map(_labFromRow).toList();
    } catch (_) {
      return [];
    }
  }

  /// النسبة الطبيعية لتحليل حسب سن/جنس/حمل المريض (null لو مفيش صف مناسب).
  Future<LabRange?> getReferenceRange(
    String labCode, {
    required int age,
    String? sex,
    bool isPregnant = false,
  }) async {
    if (!await labsAvailable()) return null;
    try {
      final rows = await _database.rawQuery('''
        SELECT r.population, r.sex, r.age_min_years, r.age_max_years,
               r.low, r.high, r.note
        FROM lab_reference_ranges r
        JOIN lab_tests l ON l.id = r.lab_id
        WHERE l.code = ?
      ''', [labCode]);
      return pickLabRange(rows, age: age, sex: sex, isPregnant: isPregnant);
    } catch (e, st) {
      debugPrint('❌ getReferenceRange error: $e\n$st');
      return null;
    }
  }

  // ── Herbs List ─────────────────────────────────────────────────────────
  // مجموعة صغيرة وثابتة (22 عشب) — بترجع الأسماء الأساسية بس للعرض كـ chips
  Future<List<String>> getAllHerbs() async {
    final rows = await _database
        .rawQuery('SELECT canonical_name FROM herbs ORDER BY canonical_name');
    return rows.map((r) => r['canonical_name'] as String).toList();
  }

  // ── Diagnosis Search ───────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> searchDiagnoses(String query) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final rows = await _database.rawQuery('''
      SELECT DISTINCT d.id, d.name, d.icd10, d.is_base
      FROM diagnoses d
      LEFT JOIN diagnosis_alias_maps dam ON dam.diagnosis_id = d.id
      LEFT JOIN diagnosis_aliases da ON da.id = dam.alias_id
      WHERE d.name_lower LIKE ? OR da.alias_lower LIKE ?
      ORDER BY d.is_base DESC, d.name
      LIMIT 20
    ''', ['%$q%', '%$q%']);
    // نسخة قابلة للتعديل — نتيجة rawQuery نفسها read-only
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  // ── Symptoms ───────────────────────────────────────────────────────────
  // جداول symptoms / diagnosis_symptoms اتضافت في DB v1.0.3. لو القاعدة
  // لسه قديمة (الجداول مش موجودة) الدوال دي بترجع fallback بدل ما تكسر.
  static const kFallbackTopSymptoms = <String>[
    'Fever',
    'Cough',
    'Shortness of breath',
    'Chest pain',
    'Nausea',
    'Vomiting',
    'Diarrhea',
    'Abdominal pain',
    'Headache',
    'Dizziness',
    'Fatigue',
    'Rash',
    'Urticaria',
    'Palpitations',
    'Edema',
    'Dysuria',
    'Polyuria',
    'Polydipsia',
    'Wheezing',
    'Seizures',
  ];

  List<String>? _symptomNamesCache;

  /// أشهر 20 عرض (بترتيب top_order)
  Future<List<String>> getTopSymptoms() async {
    try {
      final rows = await _database.rawQuery(
          'SELECT name FROM symptoms WHERE is_top = 1 ORDER BY top_order LIMIT 20');
      if (rows.isNotEmpty) return rows.map((r) => r['name'] as String).toList();
    } catch (_) {}
    return kFallbackTopSymptoms;
  }

  /// كل أسماء الأعراض في القاموس (متخزنة في الذاكرة بعد أول استدعاء)
  Future<List<String>> allSymptomNames() async {
    if (_symptomNamesCache != null) return _symptomNamesCache!;
    try {
      final rows =
          await _database.rawQuery('SELECT name FROM symptoms ORDER BY name');
      if (rows.isNotEmpty) {
        return _symptomNamesCache =
            rows.map((r) => r['name'] as String).toList();
      }
    } catch (_) {}
    return kFallbackTopSymptoms;
  }

  Future<List<String>> searchSymptoms(String query) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return [];
    final all = await allSymptomNames();
    final starts = all.where((n) => n.toLowerCase().startsWith(q));
    final contains = all.where(
        (n) => !n.toLowerCase().startsWith(q) && n.toLowerCase().contains(q));
    return [...starts, ...contains].take(8).toList();
  }

  /// true  = في عرض على الأقل من المختارين مرتبط بالتشخيص
  /// false = التشخيص ليه أعراض معروفة ولا واحد من المختارين منها
  /// null  = مش قادرين نحكم (تشخيص مالوش ربط، أو الأعراض كلها خارج القاموس،
  ///         أو القاعدة لسه قديمة) → التطبيق ما بيحذّرش
  Future<bool?> isDiagnosisCompatible({
    required int diagnosisId,
    required List<String> symptoms,
  }) async {
    if (symptoms.isEmpty) return null;
    try {
      final total = Sqflite.firstIntValue(await _database.rawQuery(
              'SELECT COUNT(*) FROM diagnosis_symptoms WHERE diagnosis_id = ?',
              [diagnosisId])) ??
          0;
      if (total == 0) return null;

      final names = symptoms.map((e) => e.toLowerCase()).toList();
      final p = names.map((_) => '?').join(',');

      final known = Sqflite.firstIntValue(await _database.rawQuery(
              'SELECT COUNT(*) FROM symptoms WHERE name_lower IN ($p)',
              names)) ??
          0;
      if (known == 0) return null; // كلهم أعراض يدوية — مفيش أساس للحكم

      final match = Sqflite.firstIntValue(await _database.rawQuery('''
        SELECT COUNT(*) FROM diagnosis_symptoms ds
        JOIN symptoms s ON s.id = ds.symptom_id
        WHERE ds.diagnosis_id = ? AND s.name_lower IN ($p)
      ''', [diagnosisId, ...names])) ?? 0;
      return match > 0;
    } catch (_) {
      return null;
    }
  }

  // ── DDI v2 / Families (DB v1.0.7) ──────────────────────────────────────────
  bool? _ddiV2Ok;
  Set<String>? _knownActives;
  final Map<String, TokenInfo> _tokenInfoCache = {};

  void _resetDdiCaches() {
    _ddiV2Ok = null;
    _knownActives = null;
    _tokenInfoCache.clear();
  }

  Future<bool> ddiV2Available() async {
    if (_ddiV2Ok != null) return _ddiV2Ok!;
    try {
      final rows = await _database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
          "('drug_groups', 'drug_families', 'drug_classes', 'ddi_rules')");
      _ddiV2Ok = rows.length == 4;
    } catch (_) {
      _ddiV2Ok = false;
    }
    return _ddiV2Ok!;
  }

  /// أسماء المواد الفعالة المعروفة (عائلات + حدود جرعات) lowercase.
  Future<Set<String>> _loadKnownActives() async {
    if (_knownActives != null) return _knownActives!;
    final out = <String>{};
    try {
      if (await ddiV2Available()) {
        final r = await _database
            .rawQuery('SELECT DISTINCT lower(ingredient) AS i FROM drug_classes');
        out.addAll(r.map((e) => e['i'] as String));
      }
      if (await _doseLimitsAvailable()) {
        final r = await _database.rawQuery(
            'SELECT DISTINCT lower(ingredient) AS i FROM generic_dose_limits');
        out.addAll(r.map((e) => e['i'] as String));
        final a = await _database.rawQuery(
            'SELECT DISTINCT alias_lower AS i FROM generic_dose_limit_aliases');
        out.addAll(a.map((e) => e['i'] as String));
      }
    } catch (e, st) {
      debugPrint('❌ _loadKnownActives error: $e\n$st');
    }
    return _knownActives = out;
  }

  /// الاسم الموحّد + هل هي مادة دوائية معروفة، لكل توكن (مع المرادفات).
  Future<Map<String, TokenInfo>> tokenInfo(Iterable<String> tokens) async {
    final base = tokens
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    final missing = base.where((t) => !_tokenInfoCache.containsKey(t)).toList();
    if (missing.isNotEmpty) {
      try {
        final known = await _loadKnownActives();
        final p = missing.map((_) => '?').join(',');
        final rows = await _database.rawQuery('''
          SELECT egypt_name, rxnav_name FROM synonyms
          WHERE lower(egypt_name) IN ($p) OR lower(rxnav_name) IN ($p)
        ''', [...missing, ...missing]);
        final adj = <String, Set<String>>{};
        for (final r in rows) {
          final a = (r['egypt_name'] as String).toLowerCase().trim();
          final b = (r['rxnav_name'] as String).toLowerCase().trim();
          adj.putIfAbsent(a, () => {a}).add(b);
          adj.putIfAbsent(b, () => {b}).add(a);
        }
        for (final t in missing) {
          final set = {t, ...?adj[t]};
          final canon = (set.toList()..sort()).first;
          _tokenInfoCache[t] = TokenInfo(canon, set.any(known.contains));
        }
      } catch (e, st) {
        debugPrint('❌ tokenInfo error: $e\n$st');
        for (final t in missing) {
          _tokenInfoCache[t] = TokenInfo(t, false);
        }
      }
    }
    return {for (final t in base) t: _tokenInfoCache[t]!};
  }

  Future<Set<String>> expandTokens(Iterable<String> tokens) =>
      _expandWithSynonyms(tokens);

  /// عضويات العائلات لمجموعة توكنز (بعد توسيعها بالمرادفات).
  Future<List<FamilyMembership>> getFamilyMemberships(
      Iterable<String> tokens) async {
    if (!await ddiV2Available()) return [];
    try {
      final tk = (await _expandWithSynonyms(tokens)).toList();
      if (tk.isEmpty) return [];
      final p = tk.map((_) => '?').join(',');
      final rows = await _database.rawQuery('''
        SELECT c.ingredient AS ingredient, c.dose_gt_mg AS dose_gt_mg,
               f.family_key AS family, f.name_ar AS family_ar,
               f.dup_severity AS dup_severity, f.route_scope AS route_scope,
               f.is_broad AS is_broad, f.sole_only AS sole_only,
               f.dup_note AS dup_note,
               COALESCE(g.group_key, 'other') AS grp,
               COALESCE(g.name_ar, '') AS group_ar,
               COALESCE(g.group_dup, 0) AS group_dup
        FROM drug_classes c
        JOIN drug_families f ON f.family_key = c.family_key
        LEFT JOIN drug_groups g ON g.group_key = f.group_key
        WHERE c.ingredient IN ($p)
      ''', tk);
      return rows
          .map((r) => FamilyMembership(
                ingredient: r['ingredient'] as String,
                family: r['family'] as String,
                familyAr: (r['family_ar'] as String?) ?? '',
                group: r['grp'] as String,
                groupAr: (r['group_ar'] as String?) ?? '',
                dupSeverity: (r['dup_severity'] as String?) ?? 'none',
                routeScope: (r['route_scope'] as String?) ?? 'any',
                isBroad: ((r['is_broad'] as num?)?.toInt() ?? 0) == 1,
                soleOnly: ((r['sole_only'] as num?)?.toInt() ?? 0) == 1,
                groupDup: ((r['group_dup'] as num?)?.toInt() ?? 0) == 1,
                doseGtMg: (r['dose_gt_mg'] as num?)?.toDouble(),
                dupNote: r['dup_note'] as String?,
              ))
          .toList();
    } catch (e, st) {
      debugPrint('❌ getFamilyMemberships error: $e\n$st');
      return [];
    }
  }

  /// كل قواعد التداخل اللي الطرفين بتوعها (a_key و b_key) موجودين في [keys].
  Future<List<DdiRuleRow>> getDdiRules(Set<String> keys) async {
    if (keys.length < 2 || !await ddiV2Available()) return [];
    try {
      final k = keys.toList();
      final p = k.map((_) => '?').join(',');
      final rows = await _database.rawQuery('''
        SELECT * FROM ddi_rules
        WHERE a_key IN ($p) AND b_key IN ($p)
      ''', [...k, ...k]);
      String? s(Map<String, Object?> r, String c) {
        final v = r[c] as String?;
        return (v == null || v.trim().isEmpty) ? null : v;
      }

      return rows
          .map((r) => DdiRuleRow(
                id: r['id'] as int,
                aKey: r['a_key'] as String,
                bKey: r['b_key'] as String,
                severity: (r['severity'] as String?) ?? 'Moderate',
                alertType: (r['alert_type'] as String?) ?? '3.0',
                effect: (r['effect'] as String?) ?? '',
                management: s(r, 'management'),
                neonateNote: s(r, 'neonate_note'),
                source: s(r, 'source'),
                sourceUrl: s(r, 'source_url'),
                verified: ((r['verified'] as num?)?.toInt() ?? 0) == 1,
              ))
          .toList();
    } catch (e, st) {
      debugPrint('❌ getDdiRules error: $e\n$st');
      return [];
    }
  }

  // ── Resolve RxCUI ──────────────────────────────────────────────────────
  // ⚠️ معطّلة — مفيش generic_id في drugs الحقيقي، ومفيش rxcui فعلي مرتبط
  // بصف دواء واحد بعينه. المطابقة بقت كلها بالاسم النصي (genericTokens).
  Future<int?> resolveRxcui(int drugId) async {
    return null;
  }

  // ── Close ──────────────────────────────────────────────────────────────
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _indHasNote = null;
    _doseLimitsOk = null;
    _labsOk = null;
    _drugLabRows = null;
    _resetDdiCaches();
  }
}
