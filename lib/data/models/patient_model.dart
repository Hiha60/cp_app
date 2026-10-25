class MedicationModel {
  final String brandName, genericName, strength, form, frequency;
  final int? rxcui;
  final String
      normalizedGenerics; // "amoxicillin|clavulanic acid" — للمطابقة النصية وقت التنبيهات
  final bool isChronic;
  // عدد الأقراص/الأمبولات في الجرعة الواحدة، أو عدد المل للسوائل. null = غير محدد
  final double? doseQty;

  const MedicationModel({
    required this.brandName,
    required this.genericName,
    this.rxcui,
    required this.strength,
    required this.form,
    required this.frequency,
    this.normalizedGenerics = '',
    this.isChronic = false,
    this.doseQty,
  });

  String get _qtyText {
    final q = doseQty;
    if (q == null) return '';
    final t = q == q.roundToDouble() ? q.toInt().toString() : q.toString();
    return ' — جرعة: $t';
  }

  String get displayText =>
      '$brandName $strength — $form$_qtyText — $frequency';

  List<String> get genericTokens => normalizedGenerics
      .split('|')
      .map((e) => e.trim().toLowerCase())
      .where((e) => e.isNotEmpty)
      .toList();

  factory MedicationModel.fromMap(Map<String, dynamic> m) => MedicationModel(
        brandName: m['brand_name'] as String? ?? '',
        genericName: m['generic_name'] as String? ?? '',
        rxcui: m['rxcui'] as int?,
        strength: m['strength'] as String? ?? '',
        form: m['form'] as String? ?? '',
        frequency: m['frequency'] as String? ?? '',
        normalizedGenerics: m['normalized_generics'] as String? ?? '',
        isChronic: m['is_chronic'] as bool? ?? false,
        doseQty: (m['dose_qty'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'brand_name': brandName,
        'generic_name': genericName,
        'rxcui': rxcui,
        'strength': strength,
        'form': form,
        'frequency': frequency,
        'normalized_generics': normalizedGenerics,
        'is_chronic': isChronic,
        'dose_qty': doseQty,
      };
}

class HerbModel {
  final String name; // الاسم الأساسي (canonical_name) من جدول herbs
  const HerbModel({required this.name});

  factory HerbModel.fromMap(Map<String, dynamic> m) =>
      HerbModel(name: m['name'] as String? ?? '');

  Map<String, dynamic> toMap() => {'name': name};
}

class AllergyModel {
  final String drugName, reactionType;
  // ⚠️ المواد الفعالة (lowercase) اللي الحساسية دي بتغطيها فعليًا — بتتحدد
  // وقت الإضافة من بيانات الدواء المختار (مش نص حر بعد كده). لو فاضية،
  // يبقى ده تسجيل قديم قبل التحديث ده وهيتفحص بالطريقة الاحتياطية القديمة.
  final List<String> allergenTokens;
  // لو الصيدلي اختار إن الحساسية من عيلة الدواء كلها مش منه هو بس
  final String? className;

  const AllergyModel({
    required this.drugName,
    required this.reactionType,
    this.allergenTokens = const [],
    this.className,
  });

  factory AllergyModel.fromMap(Map<String, dynamic> m) => AllergyModel(
        drugName: m['drug_name'] as String? ?? '',
        reactionType: m['reaction_type'] as String? ?? '',
        allergenTokens: List<String>.from(m['allergen_tokens'] ?? []),
        className: m['class_name'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'drug_name': drugName,
        'reaction_type': reactionType,
        'allergen_tokens': allergenTokens,
        'class_name': className,
      };
}

/// نتيجة تحليل مسجّلة للمريض.
///  • تحليل رقمي: value (وبالوحدة الافتراضية للتحليل في lab_tests).
///  • تحليل نوعي (زرع/سمير/مصل): value = null و abnormal = true/false.
class LabResultModel {
  final String labCode, labName, unit;
  final double? value;
  final bool? abnormal;
  final DateTime takenAt;
  final String? note;
  final String addedByUserName;

  const LabResultModel({
    required this.labCode,
    required this.labName,
    this.unit = '',
    this.value,
    this.abnormal,
    required this.takenAt,
    this.note,
    this.addedByUserName = '',
  });

  factory LabResultModel.fromMap(Map<String, dynamic> m) {
    DateTime d(dynamic v) {
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return LabResultModel(
      labCode: m['lab_code'] as String? ?? '',
      labName: m['lab_name'] as String? ?? '',
      unit: m['unit'] as String? ?? '',
      value: (m['value'] as num?)?.toDouble(),
      abnormal: m['abnormal'] as bool?,
      takenAt: d(m['taken_at']),
      note: m['note'] as String?,
      addedByUserName: m['added_by_user_name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'lab_code': labCode,
        'lab_name': labName,
        'unit': unit,
        'value': value,
        'abnormal': abnormal,
        'taken_at': takenAt.toUtc().toIso8601String(),
        'note': note,
        'added_by_user_name': addedByUserName,
      };
}

// ── المحاليل الوريدية ────────────────────────────────────────────────────────
class FluidAdditive {
  final MedicationModel med;

  /// نص تحذير "غير مناسب للوريد" لو المستخدم وافق على الاستكمال، وإلا null
  final String? ivWarning;
  const FluidAdditive({required this.med, this.ivWarning});

  Map<String, dynamic> toMap() => {'med': med.toMap(), 'iv_warning': ivWarning};
  factory FluidAdditive.fromMap(Map<String, dynamic> m) => FluidAdditive(
        med:
            MedicationModel.fromMap(Map<String, dynamic>.from(m['med'] as Map)),
        ivWarning: m['iv_warning'] as String?,
      );
}

class FluidOrder {
  final String fluidId, name;
  final List<FluidAdditive> additives;
  const FluidOrder(
      {required this.fluidId, required this.name, this.additives = const []});

  Map<String, dynamic> toMap() => {
        'fluid_id': fluidId,
        'name': name,
        'additives': additives.map((a) => a.toMap()).toList(),
      };
  factory FluidOrder.fromMap(Map<String, dynamic> m) => FluidOrder(
        fluidId: m['fluid_id'] as String? ?? '',
        name: m['name'] as String? ?? '',
        additives: (m['additives'] as List? ?? [])
            .map((e) =>
                FluidAdditive.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class PatientModel {
  final String? id;
  final String hospitalId, departmentId, addedByUserId, addedByUserName;
  final String name, fileNumber, status;
  final int age;
  // شهور إضافية (0–11) — للعرض بس، مش داخلة في أي حساب (الحسابات كلها على age بالسنين)
  final int ageMonths;
  final double? weightKg;
  final DateTime admissionDate, createdAt, updatedAt;
  final List<String> primaryDiagnoses, finalDiagnoses, comorbidities;
  // ⚠️ الـ id بتاع كل تشخيص (من جدول diagnoses) — لازم عشان فحص
  // الجرعات/المؤشر العلاجي في alert_engine.dart، لأنه بيربط بـ diagnosis_id
  final List<int> primaryDiagnosisIds, finalDiagnosisIds;
  // الأعراض (إنجليزي) — customSymptoms = اللي اتضافت يدوي خارج قاموس الأعراض
  final List<String> symptoms, customSymptoms;
  final bool hasComorbidities, hasChronicMedications, hasAllergies;
  final List<MedicationModel> chronicMedications, prescribedMedications;
  final List<AllergyModel> allergies;
  final bool hasHerbs;
  final List<HerbModel> herbs;
  // الجنس 'M' | 'F' | null (مرضى قدام) + الحمل (للنسب الطبيعية والتنبيهات)
  final String? sex;
  final bool isPregnant;
  final List<LabResultModel> labResults;
  // المحاليل الوريدية (+ الأمبولات/الفيالات المضافة عليها)
  final List<FluidOrder> fluids;

  const PatientModel({
    this.id,
    required this.hospitalId,
    required this.departmentId,
    required this.addedByUserId,
    required this.addedByUserName,
    required this.name,
    required this.age,
    this.ageMonths = 0,
    this.weightKg,
    required this.fileNumber,
    required this.admissionDate,
    this.status = 'active',
    this.primaryDiagnoses = const [],
    this.finalDiagnoses = const [],
    this.primaryDiagnosisIds = const [],
    this.finalDiagnosisIds = const [],
    this.symptoms = const [],
    this.customSymptoms = const [],
    this.hasComorbidities = false,
    this.comorbidities = const [],
    this.hasChronicMedications = false,
    this.chronicMedications = const [],
    this.hasAllergies = false,
    this.allergies = const [],
    this.hasHerbs = false,
    this.herbs = const [],
    this.prescribedMedications = const [],
    this.sex,
    this.isPregnant = false,
    this.labResults = const [],
    this.fluids = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  // ── From REST Map ─────────────────────────────────────────────────────
  factory PatientModel.fromRestMap(String id, Map<String, dynamic> m) {
    DateTime parseDate(dynamic v) {
      if (v is DateTime) return v;
      if (v is String) return DateTime.parse(v);
      return DateTime.now();
    }

    List<MedicationModel> parseMeds(dynamic list) => (list as List? ?? [])
        .map(
            (e) => MedicationModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    List<AllergyModel> parseAllergies(dynamic list) => (list as List? ?? [])
        .map((e) => AllergyModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    List<HerbModel> parseHerbs(dynamic list) => (list as List? ?? [])
        .map((e) => HerbModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    List<LabResultModel> parseLabs(dynamic list) => (list as List? ?? [])
        .map((e) => LabResultModel.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();

    return PatientModel(
      id: id,
      hospitalId: m['hospital_id'] as String? ?? '',
      departmentId: m['department_id'] as String? ?? '',
      addedByUserId: m['added_by_user_id'] as String? ?? '',
      addedByUserName: m['added_by_user_name'] as String? ?? '',
      name: m['name'] as String? ?? '',
      age: (m['age'] as num?)?.toInt() ?? 0,
      ageMonths: (m['age_months'] as num?)?.toInt() ?? 0,
      weightKg: (m['weight_kg'] as num?)?.toDouble(),
      fileNumber: m['file_number'] as String? ?? '',
      admissionDate: parseDate(m['admission_date']),
      status: m['status'] as String? ?? 'active',
      primaryDiagnoses: List<String>.from(m['primary_diagnoses'] ?? []),
      finalDiagnoses: List<String>.from(m['final_diagnoses'] ?? []),
      primaryDiagnosisIds: List<int>.from(m['primary_diagnosis_ids'] ?? []),
      finalDiagnosisIds: List<int>.from(m['final_diagnosis_ids'] ?? []),
      symptoms: List<String>.from(m['symptoms'] ?? []),
      customSymptoms: List<String>.from(m['custom_symptoms'] ?? []),
      hasComorbidities: m['has_comorbidities'] as bool? ?? false,
      comorbidities: List<String>.from(m['comorbidities'] ?? []),
      hasChronicMedications: m['has_chronic_medications'] as bool? ?? false,
      chronicMedications: parseMeds(m['chronic_medications']),
      hasAllergies: m['has_allergies'] as bool? ?? false,
      allergies: parseAllergies(m['allergies']),
      hasHerbs: m['has_herbs'] as bool? ?? false,
      herbs: parseHerbs(m['herbs']),
      prescribedMedications: parseMeds(m['prescribed_medications']),
      sex: m['sex'] as String?,
      isPregnant: m['is_pregnant'] as bool? ?? false,
      labResults: parseLabs(m['lab_results']),
      fluids: ((m['fluids'] as List?) ?? [])
          .map((e) => FluidOrder.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      createdAt: parseDate(m['created_at']),
      updatedAt: parseDate(m['updated_at']),
    );
  }

  // ── To REST Map ───────────────────────────────────────────────────────
  Map<String, dynamic> toRestMap() => {
        'hospital_id': hospitalId,
        'department_id': departmentId,
        'added_by_user_id': addedByUserId,
        'added_by_user_name': addedByUserName,
        'name': name,
        'age': age,
        'age_months': ageMonths,
        'weight_kg': weightKg,
        'file_number': fileNumber,
        'admission_date': admissionDate.toUtc().toIso8601String(),
        'status': status,
        'primary_diagnoses': primaryDiagnoses,
        'final_diagnoses': finalDiagnoses,
        'primary_diagnosis_ids': primaryDiagnosisIds,
        'final_diagnosis_ids': finalDiagnosisIds,
        'symptoms': symptoms,
        'custom_symptoms': customSymptoms,
        'has_comorbidities': hasComorbidities,
        'comorbidities': comorbidities,
        'has_chronic_medications': hasChronicMedications,
        'chronic_medications':
            chronicMedications.map((e) => e.toMap()).toList(),
        'has_allergies': hasAllergies,
        'allergies': allergies.map((e) => e.toMap()).toList(),
        'has_herbs': hasHerbs,
        'herbs': herbs.map((e) => e.toMap()).toList(),
        'prescribed_medications':
            prescribedMedications.map((e) => e.toMap()).toList(),
        'sex': sex,
        'is_pregnant': isPregnant,
        'lab_results': labResults.map((e) => e.toMap()).toList(),
        'fluids': fluids.map((e) => e.toMap()).toList(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  PatientModel copyWith({
    String? status,
    List<String>? primaryDiagnoses,
    List<String>? finalDiagnoses,
    List<String>? symptoms,
    List<String>? customSymptoms,
    List<MedicationModel>? prescribedMedications,
    List<MedicationModel>? chronicMedications,
    List<AllergyModel>? allergies,
    List<HerbModel>? herbs,
    bool? hasHerbs,
    bool? hasComorbidities,
    List<String>? comorbidities,
    bool? hasChronicMedications,
    bool? hasAllergies,
    double? weightKg,
    String? sex,
    bool? isPregnant,
    List<LabResultModel>? labResults,
    List<FluidOrder>? fluids,
  }) =>
      PatientModel(
        id: id,
        hospitalId: hospitalId,
        departmentId: departmentId,
        addedByUserId: addedByUserId,
        addedByUserName: addedByUserName,
        name: name,
        age: age,
        ageMonths: ageMonths,
        weightKg: weightKg ?? this.weightKg,
        fileNumber: fileNumber,
        admissionDate: admissionDate,
        primaryDiagnosisIds: primaryDiagnosisIds,
        finalDiagnosisIds: finalDiagnosisIds,
        symptoms: symptoms ?? this.symptoms,
        customSymptoms: customSymptoms ?? this.customSymptoms,
        status: status ?? this.status,
        primaryDiagnoses: primaryDiagnoses ?? this.primaryDiagnoses,
        finalDiagnoses: finalDiagnoses ?? this.finalDiagnoses,
        hasComorbidities: hasComorbidities ?? this.hasComorbidities,
        comorbidities: comorbidities ?? this.comorbidities,
        hasChronicMedications:
            hasChronicMedications ?? this.hasChronicMedications,
        chronicMedications: chronicMedications ?? this.chronicMedications,
        hasAllergies: hasAllergies ?? this.hasAllergies,
        allergies: allergies ?? this.allergies,
        hasHerbs: hasHerbs ?? this.hasHerbs,
        herbs: herbs ?? this.herbs,
        prescribedMedications:
            prescribedMedications ?? this.prescribedMedications,
        sex: sex ?? this.sex,
        isPregnant: isPregnant ?? this.isPregnant,
        labResults: labResults ?? this.labResults,
        fluids: fluids ?? this.fluids,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  /// سطر تشخيص مختصر للكروت: النهائي، وإلا المبدئي (مرضى قدام)، وإلا الأعراض
  String get diagnosisText {
    if (finalDiagnoses.isNotEmpty) return finalDiagnoses.first;
    if (primaryDiagnoses.isNotEmpty) return primaryDiagnoses.first;
    if (symptoms.isNotEmpty) return symptoms.take(2).join('، ');
    return '—';
  }

  /// كل التشخيصات للتقارير
  String get diagnosisListText {
    if (finalDiagnoses.isNotEmpty) return finalDiagnoses.join('، ');
    if (primaryDiagnoses.isNotEmpty) return primaryDiagnoses.join('، ');
    return '—';
  }

  /// السن للعرض: "أقل من شهر" / "3 شهور" / "2 سنة و3 شهور" / "35 سنة"
  String get ageText {
    String m(int n) => n == 1
        ? 'شهر'
        : n == 2
            ? 'شهرين'
            : n <= 10
                ? '$n شهور'
                : '$n شهر';
    if (age == 0) return ageMonths == 0 ? 'أقل من شهر' : m(ageMonths);
    return ageMonths > 0 ? '$age سنة و${m(ageMonths)}' : '$age سنة';
  }

  bool get isActive => status == 'active';
  bool get isDischarged => status == 'discharged';
  String get displayAdmission =>
      '${admissionDate.day}/${admissionDate.month}/${admissionDate.year}';
}
