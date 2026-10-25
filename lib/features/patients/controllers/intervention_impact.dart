import '../../../core/services/alert_engine.dart';
import '../../../data/models/intervention_model.dart';
import '../../../data/models/patient_model.dart';

/// تدخل متأثر بتعديل على بيانات المريض + سبب التأثر
class AffectedIntervention {
  final InterventionModel iv;
  final String reason;
  const AffectedIntervention(this.iv, this.reason);
}

/// بيقارن بيانات المريض قبل/بعد التعديل ويرجّع التدخلات اللي التعديل بيخصها:
///  • دواء اتحذف أو اتغيّر تركيزه/شكله/تكراره  → تدخلات على نفس الدواء (drug / alt)
///  • حساسية اتحذفت                            → تدخلات 2.1 (مبنية على الحساسية)
///  • تشخيص/عرض/مرض مزمن اتحذف                → تدخلات conditionName بتاعتها
List<AffectedIntervention> affectedInterventions({
  required PatientModel before,
  required PatientModel after,
  required List<InterventionModel> interventions,
}) {
  if (interventions.isEmpty) return const [];
  final out = <String, AffectedIntervention>{};

  void add(InterventionModel iv, String reason) {
    final id = iv.id;
    if (id == null) return;
    out.putIfAbsent(id, () => AffectedIntervention(iv, reason));
  }

  // ── الأدوية ───────────────────────────────────────────────────────────
  final bMeds = [...before.prescribedMedications, ...before.chronicMedications];
  final aMeds = [...after.prescribedMedications, ...after.chronicMedications];
  for (final m in bMeds) {
    final same = aMeds.where((x) => _medKey(x) == _medKey(m)).toList();
    String? why;
    if (same.isEmpty) {
      why = 'تم حذف الدواء ${m.brandName}';
    } else if (!same.any((x) =>
        x.strength == m.strength &&
        x.form == m.form &&
        x.frequency == m.frequency)) {
      why = 'تم تعديل تركيز/شكل/تكرار ${m.brandName}';
    }
    if (why == null) continue;
    final keys = _medNames(m);
    for (final iv in interventions) {
      if (_hit(iv.drugName, keys) || _hit(iv.altDrugName, keys)) add(iv, why);
    }
  }

  // ── الحساسية ──────────────────────────────────────────────────────────
  final aAllergies =
      after.allergies.map((a) => a.drugName.trim().toLowerCase()).toSet();
  for (final al in before.allergies) {
    if (aAllergies.contains(al.drugName.trim().toLowerCase())) continue;
    for (final iv in interventions) {
      // تدخل 2.1 مبني على الحساسية، والاسم التجاري فيه ممكن مايطابقش المادة
      // الفعالة المسجلة — فبنحذّر على كل تدخلات 2.1
      if (iv.typeCode == '2.1') {
        add(iv, 'تم حذف حساسية ${al.drugName}');
      }
    }
  }

  // ── التشخيصات / الأعراض / الأمراض المزمنة ────────────────────────────
  Set<String> low(Iterable<String> xs) =>
      xs.map((e) => e.trim().toLowerCase()).toSet();
  final removed = <String>[
    ..._missing(before.finalDiagnoses, low(after.finalDiagnoses)),
    ..._missing(before.symptoms, low(after.symptoms)),
    ..._missing(before.comorbidities, low(after.comorbidities)),
  ];
  for (final r in removed) {
    final keys = {r.trim().toLowerCase()};
    for (final iv in interventions) {
      if (_hit(iv.conditionName, keys)) add(iv, 'تم حذف "$r"');
    }
  }

  // ── الأعشاب ───────────────────────────────────────────────────────────
  final aHerbs = low(after.herbs.map((h) => h.name));
  for (final h in before.herbs) {
    if (aHerbs.contains(h.name.trim().toLowerCase())) continue;
    for (final iv in interventionsForHerb(h.name, interventions)) {
      add(iv, 'تم حذف العشب ${h.name}');
    }
  }

  return out.values.toList();
}

// ── مساعدات عامة (بتتستخدم في تنبيه الحذف الفوري وفي الحفظ) ─────────────────
List<InterventionModel> interventionsForMed(
    MedicationModel m, List<InterventionModel> ivs) {
  final keys = _medNames(m);
  return ivs
      .where((iv) => _hit(iv.drugName, keys) || _hit(iv.altDrugName, keys))
      .toList();
}

List<InterventionModel> interventionsForAllergy(List<InterventionModel> ivs) =>
    ivs.where((iv) => iv.typeCode == '2.1').toList();

List<InterventionModel> interventionsForCondition(
        String name, List<InterventionModel> ivs) =>
    ivs.where((iv) => _hit(iv.conditionName, {name.trim().toLowerCase()})).toList();

List<InterventionModel> interventionsForHerb(
        String name, List<InterventionModel> ivs) =>
    ivs
        .where((iv) =>
            iv.typeCode == '3.0' &&
            (_hit(iv.drugName, {name.trim().toLowerCase()}) ||
                _hit(iv.altDrugName, {name.trim().toLowerCase()})))
        .toList();

/// تنبيه متأثر بتعديل + السبب
class AffectedAlert {
  final ClinicalAlert alert;
  final String reason;
  const AffectedAlert(this.alert, this.reason);
}

List<ClinicalAlert> alertsForMed(MedicationModel m, List<ClinicalAlert> alerts) {
  final keys = _medNames(m);
  final brand = m.brandName.trim().toLowerCase();
  return alerts
      .where((a) =>
          _hit(a.drugA, keys) ||
          _hit(a.drugB, keys) ||
          (brand.length >= 3 && a.title.toLowerCase().contains(brand)))
      .toList();
}

List<ClinicalAlert> alertsForAllergy(List<ClinicalAlert> alerts) =>
    alerts.where((a) => a.typeCode == '2.1').toList();

/// تنبيهات المؤشر العلاجي (1.1) بتتأثر بأي تغيير في التشخيص/الأعراض
List<ClinicalAlert> alertsForCondition(List<ClinicalAlert> alerts) =>
    alerts.where((a) => a.typeCode == '1.1').toList();

List<ClinicalAlert> alertsForHerb(String name, List<ClinicalAlert> alerts) {
  final k = name.trim().toLowerCase();
  return alerts
      .where((a) =>
          _hit(a.drugB, {k}) ||
          _hit(a.drugA, {k}) ||
          (k.length >= 3 && a.title.toLowerCase().contains(k)))
      .toList();
}

/// التنبيهات اللي هتتغيّر/تختفي بسبب الفرق بين before و after
List<AffectedAlert> affectedAlerts({
  required PatientModel before,
  required PatientModel after,
  required List<ClinicalAlert> alerts,
}) {
  if (alerts.isEmpty) return const [];
  final out = <ClinicalAlert, AffectedAlert>{};
  void add(ClinicalAlert a, String reason) =>
      out.putIfAbsent(a, () => AffectedAlert(a, reason));

  final aMeds = [...after.prescribedMedications, ...after.chronicMedications];
  for (final m in [...before.prescribedMedications, ...before.chronicMedications]) {
    final same = aMeds.where((x) => _medKey(x) == _medKey(m)).toList();
    String? why;
    if (same.isEmpty) {
      why = 'تم حذف الدواء ${m.brandName}';
    } else if (!same.any((x) =>
        x.strength == m.strength &&
        x.form == m.form &&
        x.frequency == m.frequency)) {
      why = 'تم تعديل تركيز/شكل/تكرار ${m.brandName}';
    }
    if (why == null) continue;
    for (final a in alertsForMed(m, alerts)) {
      add(a, why);
    }
  }

  final aAllergies =
      after.allergies.map((a) => a.drugName.trim().toLowerCase()).toSet();
  for (final al in before.allergies) {
    if (aAllergies.contains(al.drugName.trim().toLowerCase())) continue;
    for (final a in alertsForAllergy(alerts)) {
      add(a, 'تم حذف حساسية ${al.drugName}');
    }
  }

  Set<String> low(Iterable<String> xs) =>
      xs.map((e) => e.trim().toLowerCase()).toSet();
  final removedConds = <String>[
    ..._missing(before.finalDiagnoses, low(after.finalDiagnoses)),
    ..._missing(before.symptoms, low(after.symptoms)),
    ..._missing(before.comorbidities, low(after.comorbidities)),
  ];
  for (final r in removedConds) {
    for (final a in alertsForCondition(alerts)) {
      add(a, 'تم حذف "$r"');
    }
  }

  final aHerbs = low(after.herbs.map((h) => h.name));
  for (final h in before.herbs) {
    if (aHerbs.contains(h.name.trim().toLowerCase())) continue;
    for (final a in alertsForHerb(h.name, alerts)) {
      add(a, 'تم حذف العشب ${h.name}');
    }
  }
  return out.values.toList();
}

Iterable<String> _missing(List<String> before, Set<String> afterLower) =>
    before.where((e) => !afterLower.contains(e.trim().toLowerCase()));

String _medKey(MedicationModel m) => m.brandName.trim().toLowerCase();

Set<String> _medNames(MedicationModel m) {
  final out = <String>{m.brandName.trim().toLowerCase()};
  final first = m.brandName.trim().split(RegExp(r'\s+')).first.toLowerCase();
  if (first.length >= 4) out.add(first);
  out.addAll(m.genericName
      .split(RegExp(r'[+|()/,]'))
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.length >= 3));
  out.addAll(m.genericTokens);
  return out..removeWhere((e) => e.length < 3);
}

bool _hit(String? text, Iterable<String> keys) {
  final t = (text ?? '').trim().toLowerCase();
  if (t.length < 3) return false;
  for (final k in keys) {
    if (k.length < 3) continue;
    if (t == k || t.contains(k) || k.contains(t)) return true;
  }
  return false;
}
