// core/services/intervention_suggester.dart
//
// اقتراحات تلقائية لحقول التدخل (مرجع / وصف الخطأ / إجراء / سبب / خطورة).
// كلها مجرد اقتراح — الصيدلاني بيقدر يغيّرها.
import '../constants/error_lists.dart';

class InterventionSuggester {
  InterventionSuggester._();

  // ── المرجع العلمي ────────────────────────────────────────────────────
  /// أفضل [max] مراجع حسب القسم + السن + التشخيص + نوع التدخل.
  static List<String> references({
    required String deptName,
    required int age,
    required List<String> diagnoses,
    required String typeCode,
    int max = 5,
  }) {
    final score = <String, int>{};
    void add(Iterable<String> names, int pts) {
      for (final n in names) {
        if (kReferences.contains(n)) score[n] = (score[n] ?? 0) + pts;
      }
    }

    bool has(String text, List<String> keys) {
      final t = text.toLowerCase();
      return keys.any((k) => t.contains(k));
    }

    final dept = deptName.toLowerCase();
    final dx = diagnoses.join(' | ').toLowerCase();

    final neonatal = has(dept, ['nicu', 'neonat', 'حضان', 'مبتسر', 'حديثي']);
    final peds = neonatal ||
        age < 18 ||
        has(dept, ['pediat', 'paediat', 'peds', 'اطفال', 'أطفال', 'طفل']);

    // ── القسم ──
    if (neonatal) {
      add(const [
        'Neofax',
        'Neonatal Formulary: Drug Use in Pregnancy and the First Year of Life',
        'BNF for Children (British National Formulary)',
        'Harriet lane Handbook',
        'Oxford Handbook of Neonatology',
      ], 4);
    }
    if (has(dept, ['icu', 'عناية', 'رعاية', 'critical'])) {
      add(const [
        'Handbook of Drugs in Intensive Care: An A-Z Guide',
        'ACCP Updates in Critical Care: Pharmacotherapy Preparatory Review & Recertification Course',
        'SSC (The Surviving Sepsis Campaign)',
        'Marino\'s The ICU Book (Paul Marino\'s)',
      ], 3);
    }
    if (has(dept, ['renal', 'kidney', 'dialysis', 'كلى', 'كلي', 'غسيل'])) {
      add(const [
        'Renal Drug Handbook: The Ultimate Prescribing Guide for Renal Practitioners',
        'KDIGO (Kidney Disease Improving Global Outcomes)',
        'Oxford Handbook of Dialysis',
      ], 3);
    }
    if (has(dept, ['cardi', 'قلب', 'ccu'])) {
      add(const [
        'AHA/ACC (American Heart Association/ American College of Cardiology)',
        'ESC (European Society of Cardiology)',
      ], 3);
    }
    if (has(dept, ['chest', 'pulmo', 'صدر', 'رئة'])) {
      add(const [
        'GOLD (Global Initiative for Chronic Obstructive Lung Disease)',
        'GINA (Global Initiative for Asthma)',
        'ATS (American Thoracic Society)',
      ], 3);
    }
    if (has(dept, ['liver', 'hepat', 'كبد'])) {
      add(const [
        'AASLD (American Association for the Study of Liver Disease)',
        'EASL (European Association for the Study of Liver)',
      ], 3);
    }
    if (has(dept, ['eye', 'ophth', 'عيون', 'رمد'])) {
      add(const [
        'AAO ( American Academy of Ophthalmology)',
        'Drug Eye',
        'ICOph (International Council of Ophthalmology)',
      ], 3);
    }
    if (has(dept, ['onco', 'اورام', 'أورام', 'tumor'])) {
      add(const [
        'ACCP Updates in Oncology: Pharmacotherapy Preparatory Review & Recertification Course',
      ], 3);
    }
    if (has(dept, ['emerg', 'طوارئ', 'استقبال'])) {
      add(const ['Oxford Handbook of Emergency Medicine'], 3);
    }
    if (has(dept, ['infect', 'عدوى', 'معدية', 'حميات'])) {
      add(const [
        'IDSA (Infectious Disease Society of America)',
        'The Sanford Guide to Antimicrobial Therapy',
        'Johns Hopkins Antibiotic Guidelines',
      ], 3);
    }
    if (has(dept, ['diab', 'endocr', 'سكر', 'غدد'])) {
      add(const [
        'diabetes.org (ADA: American Diabetes Association)',
        'JBDS-IP (The Joint British Diabetes Society for Inpatient Care)',
      ], 3);
    }
    if (has(dept, ['obst', 'gyn', 'نساء', 'توليد'])) {
      add(const [
        'Drugs During Pregnancy and Lactation: Treatment Options and Risk Assessment',
      ], 3);
    }

    // ── السن ──
    if (peds && !neonatal) {
      add(const [
        'BNF for Children (British National Formulary)',
        'Harriet lane Handbook',
        'Nelson\'s Pediatric Antimicrobial Therapy',
        'Nelson Textbook of Pediatrics',
      ], 3);
    }
    if (age >= 65) add(const ['Lexicomp', 'Uptodate'], 2);

    // ── التشخيص ──
    if (has(dx, ['diabet', 'dka', 'سكر'])) {
      add(const [
        'diabetes.org (ADA: American Diabetes Association)',
        'JBDS-IP (The Joint British Diabetes Society for Inpatient Care)',
      ], 4);
    }
    if (has(dx, [
      'hypertens', 'heart', 'cardiac', 'myocard', 'coronary',
      'atrial', 'angina', 'stemi', 'قلب', 'ضغط',
    ])) {
      add(const [
        'AHA/ACC (American Heart Association/ American College of Cardiology)',
        'ESC (European Society of Cardiology)',
      ], 4);
    }
    if (has(dx, ['asthma', 'ربو'])) {
      add(const ['GINA (Global Initiative for Asthma)'], 4);
    }
    if (has(dx, ['copd', 'chronic obstructive'])) {
      add(const ['GOLD (Global Initiative for Chronic Obstructive Lung Disease)'],
          4);
    }
    if (has(dx, ['sepsis', 'septic', 'تسمم'])) {
      add(const ['SSC (The Surviving Sepsis Campaign)'], 4);
      if (neonatal) add(const ['Evidence-Based Neonatal Infections'], 3);
    }
    if (has(dx, [
      'pneumonia', 'infection', 'uti', 'cellulitis', 'meningitis',
      'abscess', 'التهاب', 'عدوى',
    ])) {
      add(const [
        'IDSA (Infectious Disease Society of America)',
        'The Sanford Guide to Antimicrobial Therapy',
      ], 4);
    }
    if (has(dx, ['tuberc', 'درن'])) {
      add(const [
        'WHO (World Health Organization)',
        'ATS (American Thoracic Society)',
      ], 4);
    }
    if (has(dx, ['renal', 'kidney', 'ckd', 'aki', 'nephr', 'كلى', 'كلي'])) {
      add(const [
        'KDIGO (Kidney Disease Improving Global Outcomes)',
        'Renal Drug Handbook: The Ultimate Prescribing Guide for Renal Practitioners',
      ], 4);
    }
    if (has(dx, ['liver', 'hepat', 'cirrho', 'كبد'])) {
      add(const [
        'AASLD (American Association for the Study of Liver Disease)',
        'EASL (European Association for the Study of Liver)',
      ], 4);
    }
    if (has(dx, ['head injury', 'brain injury', 'tbi', 'trauma', 'إصابة'])) {
      add(const ['braintrauma.org (BRAIN TRAUMA FOUNDATION)'], 4);
    }
    if (has(dx, ['cancer', 'carcinoma', 'leuk', 'lymphoma', 'malignan', 'ورم'])) {
      add(const [
        'ACCP Updates in Oncology: Pharmacotherapy Preparatory Review & Recertification Course',
      ], 4);
    }
    if (has(dx, ['pregnan', 'lactat', 'حمل'])) {
      add(const [
        'Drugs During Pregnancy and Lactation: Treatment Options and Risk Assessment',
      ], 4);
    }
    if (has(dx, ['malnutrition', 'parenteral', 'تغذية'])) {
      add(const ['ASPEN (American Society for Parenteral and Enteral Nutrition)'],
          3);
    }

    // ── نوع التدخل ──
    final g = typeCode.split('.').first;
    switch (g) {
      case '3':
        add(const ['Lexicomp', 'Micromedex'], 3);
        break;
      case '5':
        add(
            peds
                ? const [
                    'Pediatric Injectable Drugs: The Teddy Bear Book',
                    'Trissel\'s Handbook on Injectable Drugs',
                  ]
                : const [
                    'Trissel\'s Handbook on Injectable Drugs',
                    'ASHP\'s Handbook on Injectable Drugs',
                    'Injectable Drugs Guide',
                  ],
            3);
        break;
      case '4':
        add(const ['Lexicomp', 'Micromedex'], 2);
        break;
      case '2':
        if (typeCode == '2.3') {
          add(const [
            'Handbook of Drug Administration via Enteral Feeding Tubes',
          ], 2);
        }
        add(const ['Lexicomp', 'Micromedex'], 2);
        break;
      default:
        add(const ['Uptodate', 'Lexicomp'], 2);
    }
    add(const ['Lexicomp', 'Uptodate', 'Micromedex'], 1); // أساسيات

    final list = score.keys.toList()
      ..sort((a, b) => score[b]!.compareTo(score[a]!));
    return list.take(max).toList();
  }

  // ── الخطأ الدوائي ────────────────────────────────────────────────────
  static String _stageAr(String stage) {
    if (stage.startsWith('[Ordering Decision')) return 'قرار الوصف';
    if (stage.startsWith('[Ordering Process')) return 'كتابة الأمر الدوائي';
    if (stage.startsWith('[Monitoring')) return 'المتابعة';
    if (stage.startsWith('[Administration')) return 'إعطاء الدواء';
    if (stage.startsWith('[Dispensing')) return 'صرف الدواء';
    if (stage.startsWith('[Preparation')) return 'تحضير الدواء';
    if (stage.startsWith('[Transcribing')) return 'نسخ الأمر الدوائي';
    if (stage.startsWith('[Storage')) return 'التخزين';
    return 'الوصف';
  }

  /// المرحلة المقترحة من كود المشكلة
  static String? stage(String typeCode) {
    final s = kErrorStageByType[typeCode];
    if (s != null) return s;
    if (typeCode == '6.2') {
      return kErrorStages.firstWhere((e) => e.startsWith('[Monitoring] (2)'),
          orElse: () => kErrorStages.first);
    }
    if (typeCode.startsWith('7.')) {
      return kErrorStages.firstWhere(
          (e) => e.startsWith('[Administration] (9)'),
          orElse: () => kErrorStages.first);
    }
    return null;
  }

  static String _find(List<String> list, String starts, String fallback) =>
      list.firstWhere((e) => e.startsWith(starts),
          orElse: () => list.firstWhere((e) => e.startsWith(fallback)));

  /// السبب المحتمل
  static String cause(String typeCode, int age) {
    final String c;
    switch (typeCode) {
      case '1.1':
      case '4.2':
        c = 'Unclear/Lacking documentation in medical records';
        break;
      case '1.2':
      case '6.1':
        c = 'Environmental factors (Workload-Noise - Poor communication)';
        break;
      case '2.1':
      case '2.5':
        c = 'Incomplete patient information';
        break;
      case '3.0':
      case '5.2':
      case '5.3':
        c = 'Lack of drug information sources';
        break;
      case '4.1':
        c = age < 18 ? 'Calculation error' : 'Lack of knowledge/ Experience';
        break;
      default:
        c = typeCode.startsWith('7.')
            ? 'Lack of patient education or compliance'
            : 'Lack of knowledge/ Experience';
    }
    return _find(kErrorCauses, c, 'Others');
  }

  /// الخطورة: التدخل بيحصل قبل وصول الدواء للمريض => B غالبًا
  static String severity(String typeCode) {
    final letter = typeCode.startsWith('7.')
        ? 'C'
        : typeCode == '6.2'
            ? 'D'
            : 'B';
    return _find(kErrorSeverities, '$letter ', 'B ');
  }

  /// وصف الخطأ (من تعليق التدخل)
  static String description({
    required String typeNameAr,
    required String comment,
    required String? stage,
    required String severityLetter,
  }) {
    final st = stage == null ? '' : ' في مرحلة ${_stageAr(stage)}';
    final tail = switch (severityLetter) {
      'B' => 'تم اكتشافه أثناء المراجعة الصيدلية وقبل وصول الدواء للمريض.',
      'C' => 'وصل للمريض دون ضرر.',
      'D' => 'وصل للمريض وتطلّب متابعة للتأكد من عدم حدوث ضرر.',
      _ => '',
    };
    final dot = comment.endsWith('.') ? '' : '.';
    return 'خطأ دوائي$st ($typeNameAr): $comment$dot $tail'.trim();
  }

  /// إجراء الصيدلاني
  static String action(String typeNameAr) =>
      'تم التواصل مع الطبيب المعالج وإبلاغه بالتدخل ($typeNameAr) '
      'وتوصية بتعديل الأمر الدوائي، مع متابعة تنفيذ التوصية.';
}
