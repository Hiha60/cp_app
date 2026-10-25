// lib/core/services/intervention_excel_builder.dart
//
// بيبني ملف الإكسل بنفس شكل ملف "Form Responses" المرجعي بالظبط.
// الفكرة: القالب (assets/templates/interventions_template.xlsx) هو نسخة نضيفة
// من ملف الإكسل الأصلي (نفس الألوان والخطوط والقوايم والحماية والـ Drop Downs)،
// والكود ده بيملأ الصفوف بس — مفيش أي تنسيق بيتعمل بالكود.
//
// الملف pure Dart (من غير Flutter ولا GetX) عشان يتختبر لوحده.

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  ثوابت شكل الإكسل
// ─────────────────────────────────────────────────────────────────────────────

/// عمود A (Timestamp) — في الملف المرجعي مكتوب OFFLINE
const kReportTimestampText = 'OFFLINE';

/// عمود B (Password) — نفس القيمة اللي في الملف المرجعي
const kReportPasswordText = 'AS14';

/// عدد حروف كود المريض (s.h.a3881 → 3 حروف)
const kPatientInitialsCount = 3;

/// قبول جزئي في التطبيق → إيه يتكتب في Physician Acceptance (القايمة فيها 3 بس)
const kPartialAcceptanceMapsTo = 'Accepted';

const _kMonths = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

/// style index لكل عمود A..W (نفس الـ s="" في الملف الأصلي)
const _kColStyles = <int>[
  12, 12, 13, 12, 12, 13, 21, 13, 21, 13, 12, 14, //  A..L
  15, 15, 15, 15, 16, 16, 17, 36, 36, 18, 19, //       M..W
];
const _kColLetters = [
  'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L',
  'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W',
];
const _kYesError = 'Yes it is also a medication Error';
const _kNoError = 'No Error';
const _kMinRows = 1000; // الملف الأصلي مجهّز لحد صف 1000


/// أسماء علمية بنفس المعنى (INN / USAN / BAN / أملاح) — أي اسم في المجموعة
/// بيتحوّل للاسم الموجود في Drug List بتاع الإكسل. زوّد عليها براحتك.
const kGenericSynonymGroups = <List<String>>[
  ['valproic acid', 'valproate', 'sodium valproate', 'valproate sodium', 'sodium valporate', 'valporate'],
  ['paracetamol', 'acetaminophen'],
  ['epinephrine', 'adrenaline'],
  ['norepinephrine', 'noradrenaline'],
  ['salbutamol', 'albuterol'],
  ['furosemide', 'frusemide'],
  ['glibenclamide', 'glyburide'],
  ['lidocaine', 'lignocaine'],
  ['meperidine', 'pethidine'],
  ['rifampicin', 'rifampin'],
  ['cyclosporine', 'cyclosporin', 'ciclosporin'],
  ['amoxicillin', 'amoxycillin'],
  ['sulfamethoxazole', 'sulphamethoxazole'],
  ['phenobarbital', 'phenobarbitone'],
  ['acetylsalicylic acid', 'aspirin'],
  ['clavulanic acid', 'clavulanate'],
  ['glycerin', 'glycerol'],
  ['sennosides', 'senna'],
  ['glucose', 'dextrose'],
  ['dibucaine', 'cinchocaine'],
  ['simethicone', 'dimeticone', 'activated dimeticone'],
  ['phytonadione', 'phytomenadione', 'vitamin k', 'vitamin k1'],
  ['ascorbic acid', 'vitamin c', 'vit.c'],
  ['thiamine', 'vitamin b1'],
  ['pyridoxine', 'vitamin b6'],
  ['cyanocobalamin', 'vitamin b12'],
  ['cholecalciferol', 'vitamin d3', 'vitamin d', 'vit.d'],
  ['retinol', 'vitamin a', 'vit.a'],
  ['tocopherol', 'vitamin e', 'vit.e'],
  ['benzylpenicillin', 'penicillin g'],
  ['phenoxymethylpenicillin', 'penicillin v'],
];

/// كلمات الأملاح اللي بتتشال عند المقارنة (sodium valproate ≈ valproate)
const _kSaltWords = {
  'sodium', 'potassium', 'calcium', 'magnesium', 'hydrochloride', 'hcl',
  'sulfate', 'sulphate', 'phosphate', 'acetate', 'citrate', 'maleate',
  'besylate', 'besilate', 'tartrate', 'succinate', 'mesylate', 'bromide',
  'hydrobromide', 'nitrate', 'fumarate', 'tosylate', 'disodium',
  'cilexetil', 'furoate', 'propionate', 'tromethamine', 'dihydrochloride',
  'dipropionate', 'dihydrate', 'monohydrate', 'trihydrate', 'hemihydrate',
  'anhydrous', 'hydrate', 'sesquihydrate',
};

/// نص التوصية بالإنجليزي لكل كود تدخل (نفس قوالب الإنجليزي اللي في البرنامج بالعربي)
const kEnglishRecommendationTemplates = <String, String>{
  '1.1': 'Stop [DRUG]: there is no valid indication for its use in this patient.',
  '1.2': 'Stop [DRUG] to avoid therapeutic duplication with [ALT].',
  '1.3': 'Stop [DRUG]: non-drug therapy is more appropriate for this condition.',
  '1.4': 'Add [DRUG] to treat the untreated condition: [CONDITION].',
  '1.5': 'Add [DRUG] as preventive therapy to reduce the risk of [CONDITION].',
  '1.6': 'Do not stop [DRUG] abruptly; withdraw it gradually to avoid withdrawal symptoms.',
  '1.7': 'Add [DRUG]: [CONDITION] requires additional drug therapy.',
  '2.1': 'Stop [DRUG] because of allergy and replace it with [ALT].',
  '2.2': 'Stop [DRUG]: contraindicated with [CONDITION]; replace it with [ALT].',
  '2.3': 'Change the route/dosage form of [DRUG] from [OLD] to [NEW].',
  '2.4': 'Replace [DRUG] with [ALT], the more effective option according to guidelines.',
  '2.5': 'Alert: use [DRUG] with caution because of [REASON].',
  '3.0': 'Drug interaction between [DRUG] and [ALT]. Recommendation: [REASON].',
  '4.1': 'Adjust the dose/interval of [DRUG] from [OLD] to [NEW] based on [REASON].',
  '4.2': 'Adjust the duration of [DRUG] therapy from [OLD] to [NEW].',
  '5.1': 'Administer [DRUG] at the following rate: [REASON].',
  '5.2': 'Dilute [DRUG] in [OLD] to a concentration of [NEW].',
  '5.3': '[DRUG] and [ALT] are incompatible and must not be given through the same IV line.',
  '5.4': 'Administer [DRUG] [REASON].',
  '6.1': 'Monitor [REASON] during [DRUG] therapy.',
  '6.2': '[OLD] was observed as an adverse effect of [DRUG]. Recommendation: [REASON].',
  '7.1': 'The patient was educated on how to use [DRUG].',
  '7.2': 'A reminder plan was set up to ensure regular intake of [DRUG].',
  '7.3': 'The importance of [DRUG] was discussed with the patient.',
  '7.4': 'Replace [DRUG] with [ALT] as a lower-cost alternative.',
  '7.5': 'Replace [DRUG] with [ALT] as an available alternative.',
  '7.6': "Change the route of [DRUG] from [OLD] to [NEW] to suit the patient's abilities.",
};

// ─────────────────────────────────────────────────────────────────────────────
//  Input / Output models
// ─────────────────────────────────────────────────────────────────────────────

/// بيانات تدخل واحد + المريض — قيم خام من التطبيق
class ReportInput {
  final String patientName, fileNumber, department, pharmacist;
  final DateTime date;
  final String? drugName, altDrugName;
  final String typeCode, typeNameEn;
  final String? conditionName, reason, oldValue, newValue;
  final String comment;
  final String? extraNote, reference, followUp;
  final DateTime? followUpAt;
  final String doctorResponse; // accepted | rejected | partial | considered | pending
  final bool isMedError;
  final String? errorStage, errorDescription, errorAction, errorCause, errorSeverity;

  const ReportInput({
    required this.patientName,
    required this.fileNumber,
    required this.department,
    required this.pharmacist,
    required this.date,
    this.drugName,
    this.altDrugName,
    required this.typeCode,
    required this.typeNameEn,
    this.conditionName,
    this.reason,
    this.oldValue,
    this.newValue,
    required this.comment,
    this.extraNote,
    this.reference,
    this.followUp,
    this.followUpAt,
    required this.doctorResponse,
    required this.isMedError,
    this.errorStage,
    this.errorDescription,
    this.errorAction,
    this.errorCause,
    this.errorSeverity,
  });
}

/// صف جاهز للكتابة: 23 خانة (A..W)
class ReportRow {
  final List<String> cells; // length 23
  final bool isMedError;
  const ReportRow(this.cells, this.isMedError);
}

// ─────────────────────────────────────────────────────────────────────────────
//  القوايم اللي جوه القالب (Drop Downs) — الإكسل هو المصدر الوحيد
// ─────────────────────────────────────────────────────────────────────────────

class _NormList {
  final List<String> items;
  final List<String> norms;
  _NormList(this.items) : norms = items.map(ReportMapper.norm).toList();

  String? exact(String? value) {
    final n = ReportMapper.norm(value ?? '');
    if (n.isEmpty) return null;
    for (var i = 0; i < items.length; i++) {
      if (norms[i] == n) return items[i];
    }
    return null;
  }

  /// أقرب عنصر في القايمة بفرق حروف بسيط (غلطات إملائية: valporate ≈ valproate)
  String? closest(String? value) {
    final n = ReportMapper.norm(value ?? '');
    if (n.length < 6) return null;
    final maxD = n.length >= 10 ? 3 : 2;
    String? best;
    var bestD = maxD + 1;
    for (var i = 0; i < items.length; i++) {
      final m = norms[i];
      if ((m.length - n.length).abs() > maxD) continue;
      final d = _lev(n, m, bestD);
      if (d < bestD) {
        bestD = d;
        best = items[i];
      }
    }
    return best;
  }

  static int _lev(String a, String b, int cap) {
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= b.length; j++) {
        final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j - 1] + c;
        if (prev[j] + 1 < v) v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin >= cap) return cap;
      prev = cur;
    }
    return prev[b.length];
  }

  /// exact أولًا، وبعدين أقصر عنصر بيحتوي القيمة (أو العكس)
  String? match(String? value) {
    final e = exact(value);
    if (e != null) return e;
    final n = ReportMapper.norm(value ?? '');
    if (n.length < 4) return null;
    String? best;
    for (var i = 0; i < items.length; i++) {
      final ni = norms[i];
      if (ni.contains(n) || (ni.length >= 5 && n.contains(ni))) {
        if (best == null || items[i].length < best.length) best = items[i];
      }
    }
    return best;
  }
}

class TemplateLists {
  final List<String> problemTypes, acceptance;
  final _NormList drugs, references, errorStages, causes, severities;

  /// Problem Type → Stage and Type of The Error (الجدول Table2 في الإكسل)
  final Map<String, String> stageByProblem;

  TemplateLists._({
    required this.problemTypes,
    required this.acceptance,
    required this.drugs,
    required this.references,
    required this.errorStages,
    required this.causes,
    required this.severities,
    required this.stageByProblem,
  });

  /// بيقرأ القوايم من شيت "Drop Downs" جوه القالب
  factory TemplateLists.fromTemplate(Uint8List templateBytes) {
    final zip = ZipDecoder().decodeBytes(templateBytes);
    final sst = _parseSharedStrings(_text(zip, 'xl/sharedStrings.xml'));
    final cols = _readColumns(_text(zip, 'xl/worksheets/sheet2.xml'), sst);

    List<String> col(String c) {
      final m = cols[c] ?? const <int, String>{};
      final rows = m.keys.where((r) => r >= 2).toList()..sort();
      return [
        for (final r in rows)
          if (m[r]!.trim().isNotEmpty) m[r]!,
      ];
    }

    final n = cols['N'] ?? const <int, String>{};
    final o = cols['O'] ?? const <int, String>{};
    final map = <String, String>{};
    for (final r in n.keys) {
      if (r >= 2 && o.containsKey(r)) map[n[r]!] = o[r]!;
    }

    return TemplateLists._(
      problemTypes: col('G'),
      acceptance: col('H'),
      drugs: _NormList(col('C')),
      references: _NormList(col('I')),
      errorStages: _NormList(col('K')),
      causes: _NormList(col('L')),
      severities: _NormList(col('M')),
      stageByProblem: map,
    );
  }

  /// هل الاسم موجود حرفيًا في Drug List (يعني اسم علمي)؟
  bool isGeneric(String name) => drugs.exact(name) != null;

  static String _text(Archive zip, String name) {
    final f = zip.findFile(name);
    if (f == null) throw StateError('القالب ناقص: $name');
    return utf8.decode((f.content as List).cast<int>());
  }

  static List<String> _parseSharedStrings(String xml) {
    final out = <String>[];
    final si = RegExp(r'<si>(.*?)</si>', dotAll: true);
    final t = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);
    for (final m in si.allMatches(xml)) {
      final sb = StringBuffer();
      for (final x in t.allMatches(m.group(1)!)) {
        sb.write(_unescape(x.group(1)!));
      }
      out.add(sb.toString());
    }
    return out;
  }

  /// column letter → (row → text)
  static Map<String, Map<int, String>> _readColumns(
      String sheetXml, List<String> sst) {
    final cols = <String, Map<int, String>>{};
    final cell = RegExp(r'<c r="([A-Z]+)(\d+)"([^>]*?)(?:/>|>(.*?)</c>)',
        dotAll: true);
    final vTag = RegExp(r'<v>(\d+)</v>');
    final tTag = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true);
    for (final m in cell.allMatches(sheetXml)) {
      final inner = m.group(4);
      if (inner == null) continue;
      final attrs = m.group(3) ?? '';
      String? v;
      if (attrs.contains('t="s"')) {
        final idx = vTag.firstMatch(inner);
        if (idx != null) {
          final i = int.parse(idx.group(1)!);
          if (i < sst.length) v = sst[i];
        }
      } else if (attrs.contains('t="inlineStr"')) {
        final t = tTag.firstMatch(inner);
        if (t != null) v = _unescape(t.group(1)!);
      }
      if (v == null) continue;
      (cols[m.group(1)!] ??= {})[int.parse(m.group(2)!)] = v;
    }
    return cols;
  }

  static String _unescape(String s) => s
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

// ─────────────────────────────────────────────────────────────────────────────
//  Mapper: بيانات التطبيق → خانات الإكسل (بالإنجليزي، ومن القوايم)
// ─────────────────────────────────────────────────────────────────────────────

class _Drug {
  final String generic, brand;
  const _Drug(this.generic, this.brand);
}

class ReportMapper {
  final TemplateLists lists;

  /// الاسم التجاري (lowercase) → الاسم العلمي (من قاعدة بيانات الأدوية)
  final Map<String, String> brandToGeneric;

  ReportMapper(this.lists, {this.brandToGeneric = const {}});

  static final _arabic = RegExp(r'[؀-ۿ]');
  static bool hasArabic(String s) => _arabic.hasMatch(s);

  /// بيشيل أي حاجة غير حروف/أرقام ويحوّل لـ lowercase (للمقارنة بس)
  static String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9؀-ۿ]+'), '');

  static String monthLabel(DateTime d) =>
      '${d.year} (${d.month.toString().padLeft(2, '0')}) ${_kMonths[d.month - 1]}';

  /// ٠١٢٣٤٥٦٧٨٩ / ۰۱۲۳۴۵۶۷۸۹ → 0123456789
  static String westernDigits(String s) {
    final sb = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        sb.writeCharCode(0x30 + r - 0x0660);
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        sb.writeCharCode(0x30 + r - 0x06F0);
      } else {
        sb.writeCharCode(r);
      }
    }
    return sb.toString();
  }

  /// "AUGMENTIN 1 GM 14 TABS. 1 G — مرتين يوميا" → "AUGMENTIN 1 GM 14 TABS. 1 G"
  static String cleanDrugText(String? s) =>
      (s ?? '').split(' — ').first.trim();

  /// "+" معناها مادتين مختلفين → بناخد أول واحدة بس:
  /// "Amoxicillin + Clavulanic Acid" → "Amoxicillin"
  /// أما "Sodium valproate" فاسم واحد مركّب وبيفضل زي ما هو.
  static String firstIngredient(String generic) =>
      generic.split('+').first.trim();

  // ── كود المريض: s.h/3881 ───────────────────────────────────────────────
  static const _ar2en = <String, String>{
    'ا': 'a', 'أ': 'a', 'آ': 'a', 'ٱ': 'a', 'إ': 'e', 'ء': 'a', 'ؤ': 'w', 'ئ': 'y',
    'ب': 'b', 'ت': 't', 'ث': 'th', 'ج': 'g', 'ح': 'h', 'خ': 'kh', 'د': 'd',
    'ذ': 'z', 'ر': 'r', 'ز': 'z', 'س': 's', 'ش': 'sh', 'ص': 's', 'ض': 'd',
    'ط': 't', 'ظ': 'z', 'ع': 'a', 'غ': 'gh', 'ف': 'f', 'ق': 'q', 'ك': 'k',
    'ل': 'l', 'م': 'm', 'ن': 'n', 'ه': 'h', 'ة': 'h', 'و': 'w', 'ي': 'y', 'ى': 'y',
  };

  /// أول حرف من أول [maxLetters] كلمات (بحروف إنجليزي، lowercase) مفصولة بنقط،
  /// وبعدها رقم الملف على طول — زي: "أحمد شريف علي" + 3881 → a.sh.a3881
  static String patientCode(String name, String fileNumber,
      {int maxLetters = kPatientInitialsCount}) {
    final letters = <String>[];
    for (var w in name.trim().split(RegExp(r'\s+'))) {
      if (letters.length >= maxLetters) break;
      w = w.replaceAll(RegExp(r'[^؀-ۿA-Za-z]'), '');
      if (w.isEmpty) continue;
      if (w.length > 3 && w.startsWith('ال')) w = w.substring(2);
      final ch = w[0];
      final mapped = _ar2en[ch] ??
          (RegExp(r'[A-Za-z]').hasMatch(ch) ? ch.toLowerCase() : '');
      if (mapped.isNotEmpty) letters.add(mapped);
    }
    final file = westernDigits(fileNumber.trim());
    return letters.isEmpty ? file : '${letters.join('.')}/$file';
  }

  /// الاسم العلمي → اسم من Drug List (بالترتيب):
  /// تطابق تام ← احتواء ← مرادفات ← إزالة الأملاح ← غلطة إملائية بسيطة.
  /// لو ملقاش → null (والخانة بتفضل فاضية)
  String? _genericFromList(String name) {
    final d = lists.drugs;
    final e = d.exact(name);
    if (e != null) return e;

    String strip(String x) => x
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty && !_kSaltWords.contains(w))
        .join(' ');
    final n = norm(name);
    final sn = strip(name);

    // مرادفات
    for (final g in kGenericSynonymGroups) {
      final hit = g.any((m) => norm(m) == n || (sn.isNotEmpty && strip(m) == sn));
      if (!hit) continue;
      for (final m in g) {
        final x = d.exact(m);
        if (x != null) return x;
      }
    }
    // نفس الاسم بعد إزالة الأملاح من الطرفين
    if (sn.isNotEmpty) {
      for (final item in d.items) {
        if (strip(item) == sn) return item;
      }
    }
    // كل كلمات الاسم موجودة في عنصر من القايمة
    // (levocetirizine ⊂ Levocetirizine dihydrochloride) → أقصر عنصر
    final nw = sn.split(' ').where((w) => w.isNotEmpty).toList();
    if (nw.isNotEmpty) {
      String? best;
      for (final item in d.items) {
        if (item.contains('+')) continue; // مش بنحوّل مادة لتركيبة
        final iw = item
            .toLowerCase()
            .split(RegExp(r'[^a-z0-9]+'))
            .where((w) => w.isNotEmpty)
            .toSet();
        if (nw.every(iw.contains) && (best == null || item.length < best.length)) {
          best = item;
        }
      }
      if (best != null) return best;
    }
    // غلطة إملائية بسيطة (على الاسم بعد شيل الأملاح كمان)
    return d.closest(name) ?? (sn.isNotEmpty && sn != name.toLowerCase() ? d.closest(sn) : null);
  }

  // ── الدوا: Generic (من القايمة) + Brand ───────────────────────────────────
  _Drug _drug(String? typedRaw) {
    final t = cleanDrugText(typedRaw);
    if (t.isEmpty) return const _Drug('', '');
    final exact = lists.drugs.exact(t);
    if (exact != null) return _Drug(exact, '');
    final g = brandToGeneric[t.toLowerCase()];
    if (g != null && g.trim().isNotEmpty) {
      // أول مادة فعالة بس، ومن القايمة بس (لو مش موجودة بنسيبها فاضية)
      final first = firstIngredient(g);
      // "PARACETAMOL(ACETAMINOPHEN)" → نجرّب الاسمين
      final pm = RegExp(r'^(.*?)\s*\((.*?)\)\s*$').firstMatch(first);
      final cands = pm == null ? [first] : [pm.group(1)!, pm.group(2)!];
      String? hit;
      for (final c in cands) {
        hit = _genericFromList(c);
        if (hit != null) break;
      }
      return _Drug(hit ?? lists.drugs.exact(g) ?? '', t);
    }
    final fuzzy = lists.drugs.match(t);
    if (fuzzy != null) return _Drug(fuzzy, t);
    return _Drug('', t);
  }

  String _problemType(ReportInput i) {
    final needle = '(${i.typeCode})';
    for (final p in lists.problemTypes) {
      if (p.contains(needle)) return p;
    }
    return '${i.typeCode} ${i.typeNameEn}'.trim();
  }

  String _acceptance(String r) {
    final want = switch (r) {
      'accepted' => 'Accepted',
      'rejected' => 'Rejected',
      'considered' => 'Considered',
      'partial' => kPartialAcceptanceMapsTo,
      _ => '',
    };
    if (want.isEmpty) return '';
    for (final a in lists.acceptance) {
      if (a.toLowerCase() == want.toLowerCase()) return a;
    }
    return want;
  }

  String _severity(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return '';
    final m = RegExp(r'^([A-Ia-i])(?![A-Za-z])').firstMatch(t);
    if (m != null) {
      final letter = m.group(1)!.toUpperCase();
      for (final s in lists.severities.items) {
        if (s.startsWith('$letter ') || s.startsWith('$letter(')) return s;
      }
    }
    return lists.severities.match(t) ?? t;
  }

  String _fill(String template, ReportInput i) {
    String v(String? x) => (x == null || x.trim().isEmpty) ? '—' : x.trim();
    return template
        .replaceAll('[DRUG]', v(cleanDrugText(i.drugName)))
        .replaceAll('[ALT]', v(cleanDrugText(i.altDrugName)))
        .replaceAll('[OLD]', v(i.oldValue))
        .replaceAll('[NEW]', v(i.newValue))
        .replaceAll('[CONDITION]', v(i.conditionName))
        .replaceAll('[REASON]', v(i.reason));
  }

  String _finding(ReportInput i) {
    final cond = (i.conditionName ?? '').trim();
    final base = i.typeNameEn.trim();
    return cond.isEmpty ? base : '$base: $cond';
  }

  String _recommendation(ReportInput i) {
    final c = i.comment.trim();
    final base = (c.isNotEmpty && !hasArabic(c))
        ? c
        : _fill(kEnglishRecommendationTemplates[i.typeCode] ?? i.typeNameEn, i);
    final note = (i.extraNote ?? '').trim();
    return note.isEmpty ? base : '$base | $note';
  }

  String _followUp(ReportInput i) {
    final f = (i.followUp ?? '').trim();
    if (f.isEmpty) return '';
    final d = i.followUpAt;
    if (d == null) return f;
    final l = d.toLocal();
    return '$f (${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year})';
  }

  ReportRow map(ReportInput i) {
    final a = _drug(i.drugName);
    final b = _drug(i.altDrugName);
    final problem = _problemType(i);
    final finding = _finding(i);
    final recommendation = _recommendation(i);
    final isDtp = i.typeCode.trim().isNotEmpty;

    var stage = '', errDesc = '', errAction = '', cause = '', severity = '';
    if (i.isMedError) {
      final rawStage = (i.errorStage ?? '').trim();
      stage = lists.errorStages.match(rawStage) ??
          (rawStage.isNotEmpty ? rawStage : (lists.stageByProblem[problem] ?? ''));
      errDesc = (i.errorDescription ?? '').trim().isNotEmpty
          ? i.errorDescription!.trim()
          : finding;
      errAction = (i.errorAction ?? '').trim().isNotEmpty
          ? i.errorAction!.trim()
          : recommendation;
      severity = _severity(i.errorSeverity);
    }
    final rawCause = (i.errorCause ?? '').trim();
    if (rawCause.isNotEmpty) cause = lists.causes.match(rawCause) ?? rawCause;

    final ref = (i.reference ?? '').trim();
    final local = i.date.toLocal();

    final cells = <String>[
      kReportTimestampText, //                                  A Timestamp
      kReportPasswordText, //                                   B Password
      patientCode(i.patientName, i.fileNumber), //              C Patient Information
      i.department.trim(), //                                   D Department (Ward)
      monthLabel(local), //                                     E Date
      i.pharmacist.trim(), //                                   F Clinical Pharmacist Name
      a.generic, //                                             G Main Drug (Generic)
      a.brand, //                                               H Main Drug (Brand)
      b.generic, //                                             I Second Drug (Generic)
      b.brand, //                                               J Second Drug (Brand)
      isDtp ? 'Yes' : 'No it is a Medication Error Only', //    K Is this a DTP?
      isDtp ? problem : '', //                                  L Problem Type
      finding, //                                               M Finding/Problem Description
      recommendation, //                                        N Recommendation/Intervention
      ref.isEmpty ? '' : (lists.references.match(ref) ?? ref), // O Reference
      _followUp(i), //                                          P Follow Up
      _acceptance(i.doctorResponse), //                         Q Physician Acceptance
      i.isMedError ? _kYesError : _kNoError, //                 R Also a medication error?
      stage, //                                                 S Stage and Type of The Error
      errDesc, //                                               T Error Description
      errAction, //                                             U Your action
      cause, //                                                 V Possible Causes
      severity, //                                              W Error Category (Severity)
    ];
    return ReportRow(cells, i.isMedError);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Builder: بيملأ القالب
// ─────────────────────────────────────────────────────────────────────────────

class InterventionExcelBuilder {
  InterventionExcelBuilder._();

  static Uint8List build({
    required Uint8List template,
    required List<ReportRow> rows,
    List<String> departments = const [],
    List<String> pharmacists = const [],
  }) {
    final zip = ZipDecoder().decodeBytes(template);
    final lastRow = rows.length + 1 > _kMinRows ? rows.length + 1 : _kMinRows;

    final depts = _dedupe(departments).take(50).toList();
    final pharms = _dedupe(pharmacists).take(50).toList();

    final out = Archive();
    for (final f in zip.files) {
      if (!f.isFile) continue;
      List<int> data = (f.content as List).cast<int>();
      switch (f.name) {
        case 'xl/worksheets/sheet1.xml':
          data = utf8.encode(_patchSheet1(utf8.decode(data), rows, lastRow));
          break;
        case 'xl/worksheets/sheet2.xml':
          data = utf8.encode(_patchSheet2(utf8.decode(data), depts, pharms));
          break;
        case 'xl/tables/table3.xml':
          data = utf8.encode(utf8
              .decode(data)
              .replaceAll('{{DEPT_REF}}', _ref('A', depts.length)));
          break;
        case 'xl/tables/table4.xml':
          data = utf8.encode(utf8
              .decode(data)
              .replaceAll('{{PH_REF}}', _ref('B', pharms.length)));
          break;
      }
      out.addFile(ArchiveFile(f.name, data.length, data));
    }
    final enc = ZipEncoder().encode(out);
    if (enc == null) throw StateError('فشل ضغط ملف الإكسل');
    return Uint8List.fromList(enc);
  }

  static List<String> _dedupe(List<String> xs) {
    final seen = <String>{};
    final out = <String>[];
    for (final x in xs) {
      final t = x.trim();
      if (t.isEmpty) continue;
      if (seen.add(t.toLowerCase())) out.add(t);
    }
    return out;
  }

  static String _ref(String col, int n) => '${col}1:$col${(n < 1 ? 1 : n) + 1}';

  // ── sheet1: Form Responses ────────────────────────────────────────────────
  static String _patchSheet1(String xml, List<ReportRow> rows, int lastRow) {
    // لو الصفوف أكتر من 1000 نوسّع الـ validations والـ conditional formats
    // (لازم قبل ما نحط الصفوف عشان ما نغيّرش أرقام الخلايا)
    if (lastRow > _kMinRows) {
      xml = xml.replaceAllMapped(
          RegExp(r'(?<=[A-Z])1000(?!\d)'), (_) => '$lastRow');
    }
    final sb = StringBuffer();
    for (var i = 0; i < rows.length; i++) {
      sb.write(_row(i + 2, rows[i]));
    }
    for (var r = rows.length + 2; r <= lastRow; r++) {
      sb.write(_row(r, null));
    }
    return xml.replaceFirst('{{DATA_ROWS}}', sb.toString());
  }

  static String _row(int r, ReportRow? row) {
    final sb = StringBuffer(
        '<row r="$r" spans="1:23" ht="14.25" customHeight="1" x14ac:dyDescent="0.2">');
    for (var c = 0; c < 23; c++) {
      final ref = '${_kColLetters[c]}$r';
      final style = _kColStyles[c];
      final value = row == null ? '' : row.cells[c];
      // S / T / U: في الملف الأصلي معادلات بتتملي لوحدها لو فيه Medication Error.
      // لو الصف مفيهوش خطأ دوائي بنسيب المعادلة زي ما هي (تفضل شغالة لو المستخدم غيّر R).
      if (c >= 18 && c <= 20 && (row == null || !row.isMedError)) {
        sb.write('<c r="$ref" s="$style" t="str"><f>${_formula(c, r)}</f><v></v></c>');
        continue;
      }
      sb.write(_cell(ref, style, value));
    }
    sb.write('</row>');
    return sb.toString();
  }

  static String _formula(int c, int r) => switch (c) {
        18 =>
          'IF(\$R$r="$_kYesError", VLOOKUP(\$L$r, Table2[], 2,FALSE), "")',
        19 => 'IF(\$R$r="$_kYesError",\$M$r,"")',
        _ => 'IF(\$R$r="$_kYesError",\$N$r,"")',
      };

  static String _cell(String ref, int style, String v) {
    if (v.isEmpty) return '<c r="$ref" s="$style"/>';
    final t = v.length > 32000 ? v.substring(0, 32000) : v;
    return '<c r="$ref" s="$style" t="inlineStr"><is><t xml:space="preserve">${_esc(t)}</t></is></c>';
  }

  // ── sheet2: Drop Downs (Departments + Pharmacist Names) ───────────────────
  static String _patchSheet2(
      String xml, List<String> depts, List<String> pharms) {
    return xml.replaceAllMapped(RegExp(r'\{\{([AB])(\d+)\}\}'), (m) {
      final col = m.group(1)!;
      final idx = int.parse(m.group(2)!) - 2;
      final list = col == 'A' ? depts : pharms;
      if (idx < 0 || idx >= list.length) return '';
      final style = col == 'A' ? 23 : 1;
      return '<c r="${col}${idx + 2}" s="$style" t="inlineStr"><is><t xml:space="preserve">${_esc(list[idx])}</t></is></c>';
    });
  }

  static String _esc(String s) {
    final sb = StringBuffer();
    for (final r in s.runes) {
      final ok = r == 0x9 ||
          r == 0xA ||
          r == 0xD ||
          (r >= 0x20 && r <= 0xD7FF) ||
          (r >= 0xE000 && r <= 0xFFFD) ||
          (r >= 0x10000 && r <= 0x10FFFF);
      if (!ok) continue; // حروف غير مسموحة في XML
      switch (r) {
        case 0x26:
          sb.write('&amp;');
          break;
        case 0x3C:
          sb.write('&lt;');
          break;
        case 0x3E:
          sb.write('&gt;');
          break;
        case 0x22:
          sb.write('&quot;');
          break;
        default:
          sb.writeCharCode(r);
      }
    }
    return sb.toString();
  }
}
