import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/drug_classes.dart';
import '../../../core/services/local_db_service.dart';
import '../../auth/controllers/auth_controller.dart';
import '../controllers/add_patient_controller.dart';
import 'drug_picker_widget.dart';
import 'fluid_section.dart';

class AddPatientScreen extends StatelessWidget {
  const AddPatientScreen({super.key});

  static const _steps = [
    'البيانات الأساسية',
    'التشخيص',
    'التاريخ الطبي',
    'الأدوية'
  ];

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(AddPatientController());

    // الشاشة دي تاب جوه HomeScreen (عنده Scaffold/AppBar خاص بيه)،
    // فمفيش Scaffold ولا AppBar ولا زر رجوع هنا.
    return Material(
      color: AppColors.surface,
      child: Column(
        children: [
          _StepIndicator(ctrl: ctrl, steps: _steps),
          Expanded(
            child: PageView(
              controller: ctrl.pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _Step1Basic(ctrl: ctrl),
                _Step2Diagnosis(ctrl: ctrl),
                _Step3Medical(ctrl: ctrl),
                _Step4Medications(ctrl: ctrl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STEP INDICATOR
// ─────────────────────────────────────────────────────────────────────────────
class _StepIndicator extends StatelessWidget {
  final AddPatientController ctrl;
  final List<String> steps;
  const _StepIndicator({required this.ctrl, required this.steps});

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Obx(() => Row(
              children: List.generate(steps.length * 2 - 1, (i) {
                if (i.isOdd) {
                  // connector line
                  final done = ctrl.currentStep.value > i ~/ 2;
                  return Expanded(
                    child: Container(
                      height: 2,
                      color: done ? AppColors.primary : Colors.grey.shade200,
                    ),
                  );
                }
                final idx = i ~/ 2;
                final isDone = ctrl.currentStep.value > idx;
                final isCurrent = ctrl.currentStep.value == idx;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: isDone
                            ? AppColors.success
                            : isCurrent
                                ? AppColors.primary
                                : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: isDone
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 16)
                            : Text('${idx + 1}',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isCurrent
                                      ? Colors.white
                                      : Colors.grey.shade500,
                                )),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      steps[idx],
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10,
                        color: isCurrent
                            ? AppColors.primary
                            : Colors.grey.shade400,
                        fontWeight:
                            isCurrent ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                );
              }),
            )),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  STEP 1 — البيانات الأساسية
// ─────────────────────────────────────────────────────────────────────────────
class _Step1Basic extends StatelessWidget {
  final AddPatientController ctrl;
  const _Step1Basic({required this.ctrl});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: ctrl.formKeyBasic,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // مدير المستشفى: يختار قسم المريض
              if (AuthController.to.user.isAdmin) ...[
                _FieldLabel('قسم المريض'),
                Obx(() {
                  final depts = ctrl.hospitalDepts.toList();
                  final sel = ctrl.selectedDeptId.value;
                  return DropdownButtonFormField<String>(
                    value: depts.any((d) => d.id == sel) ? sel : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.apartment_rounded),
                        hintText: 'اختار القسم'),
                    items: depts
                        .map((d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(d.name,
                                style: const TextStyle(fontFamily: 'Cairo'))))
                        .toList(),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'اختار القسم' : null,
                    onChanged: (v) => ctrl.selectedDeptId.value = v ?? '',
                  );
                }),
                const SizedBox(height: 16),
              ],
              // اسم المريض
              _FieldLabel('اسم المريض'),
              TextFormField(
                controller: ctrl.nameCtrl,
                focusNode: ctrl.nameFocus,
                validator: ctrl.validateName,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => ctrl.ageFocus.requestFocus(),
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  hintText: 'الاسم كاملاً',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 16),

              // السن: سنين + شهور (للرضّع اكتب الشهور بس واترك السنة فاضية)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel('السن (سنة)'),
                        TextFormField(
                          controller: ctrl.ageCtrl,
                          focusNode: ctrl.ageFocus,
                          validator: ctrl.validateAge,
                          onChanged: ctrl.onAgeChanged,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              ctrl.monthsFocus.requestFocus(),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            hintText: '0',
                            prefixIcon: Icon(Icons.cake_outlined, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel('الشهور (اختياري)'),
                        TextFormField(
                          controller: ctrl.monthsCtrl,
                          focusNode: ctrl.monthsFocus,
                          validator: ctrl.validateMonths,
                          onChanged: ctrl.onMonthsChanged,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              ctrl.weightFocus.requestFocus(),
                          maxLength: 2,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            hintText: '0–11',
                            counterText: '',
                            prefixIcon:
                                Icon(Icons.child_care_outlined, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'لو الطفل أقل من سنة: اكتب الشهور بس واترك السنة فاضية',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: AppColors.textSecond),
                ),
              ),
              const SizedBox(height: 16),

              // الوزن (تقديري تلقائي لو السن أقل من 12 سنة)
              _FieldLabel('الوزن (kg) — اختياري'),
              TextFormField(
                controller: ctrl.weightCtrl,
                focusNode: ctrl.weightFocus,
                onChanged: ctrl.onWeightEdited,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => ctrl.fileNumFocus.requestFocus(),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  hintText: '70',
                  prefixIcon: Icon(Icons.monitor_weight_outlined, size: 18),
                ),
              ),
              Obx(() {
                if (ctrl.weightEstimated.value) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'وزن تقديري حسب السن (معادلة APLS) — عدّله لو الوزن الفعلي معروف',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: AppColors.warning),
                    ),
                  );
                }
                if (ctrl.weightManual.value && ctrl.canEstimateWeight.value) {
                  return Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: ctrl.useEstimatedWeight,
                      child: const Text('استخدم الوزن التقديري للسن',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
              const SizedBox(height: 16),

              // الجنس + الحمل (اختياري — بيحدد النسب الطبيعية للتحاليل)
              _FieldLabel('الجنس (اختياري)'),
              Obx(() => SegmentedButton<String>(
                    emptySelectionAllowed: true,
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'M', label: Text('ذكر')),
                      ButtonSegment(value: 'F', label: Text('أنثى')),
                    ],
                    selected: ctrl.sex.value == null
                        ? <String>{}
                        : {ctrl.sex.value!},
                    onSelectionChanged: (s) {
                      ctrl.setSex(s.isEmpty ? null : s.first);
                    },
                  )),
              // خانة الحمل: أنثى + سن من 13 لـ 55 فقط
              Obx(() => ctrl.canBePregnant
                  ? SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('حامل',
                          style: TextStyle(fontFamily: 'Cairo')),
                      value: ctrl.isPregnant.value,
                      onChanged: (v) => ctrl.isPregnant.value = v,
                    )
                  : const SizedBox.shrink()),
              const SizedBox(height: 16),

              // رقم الملف
              _FieldLabel('رقم الملف'),
              TextFormField(
                controller: ctrl.fileNumCtrl,
                focusNode: ctrl.fileNumFocus,
                validator: ctrl.validateFileNum,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  hintText: 'مثال: 2024-00123',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // تاريخ الدخول
              _FieldLabel('تاريخ الدخول'),
              Obx(() => InkWell(
                    onTap: () => ctrl.pickDate(context),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 18, color: AppColors.textSecond),
                          const SizedBox(width: 12),
                          Text(
                            ctrl.selectedDate.value == null
                                ? 'اختر التاريخ'
                                : '${ctrl.selectedDate.value!.day}/${ctrl.selectedDate.value!.month}/${ctrl.selectedDate.value!.year}',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              color: ctrl.selectedDate.value == null
                                  ? Colors.grey.shade400
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),

              const SizedBox(height: 32),
              _NavButtons(ctrl: ctrl, isLast: false),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  STEP 2 — التشخيص
// ─────────────────────────────────────────────────────────────────────────────
class _Step2Diagnosis extends StatelessWidget {
  final AddPatientController ctrl;
  const _Step2Diagnosis({required this.ctrl});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── الأعراض ──────────────────────────────────────────────
            _SectionHeader('الأعراض (Symptoms)'),
            const Text(
              'علّم على الأعراض الشائعة، أو ابحث/اكتب عرض تاني بالإنجليزية',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: AppColors.textSecond),
            ),
            const SizedBox(height: 10),
            _SymptomsPicker(ctrl: ctrl),

            const SizedBox(height: 24),

            // ── التشخيص النهائي ──────────────────────────────────────
            _SectionHeader('التشخيص النهائي'),
            const Text(
              'الأشهر لسن المريض (اضغط للاختيار)، أو ابحث عن غيرها:',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: AppColors.textSecond),
            ),
            const SizedBox(height: 8),
            DxShortcutChips(ctrl: ctrl, comorbidity: false),
            const SizedBox(height: 10),
            DiagnosisSearch(
              ctrl: ctrl,
              onSelect: ctrl.addFinalDiagnosis,
              hint: 'ابحث عن التشخيص...',
            ),
            Obx(() {
              final items = ctrl.finalDiagnoses.toList();
              return DiagnosisTags(
                items: items,
                onRemove: ctrl.removeFinalDiagnosis,
                color: AppColors.success,
              );
            }),
            _LabsPreviewCard(ctrl: ctrl),

            const SizedBox(height: 32),
            _NavButtons(ctrl: ctrl, isLast: false),
          ],
        ),
      );
}

// ── Symptoms Picker ──────────────────────────────────────────────────────────
class _SymptomsPicker extends StatefulWidget {
  final AddPatientController ctrl;
  const _SymptomsPicker({required this.ctrl});
  @override
  State<_SymptomsPicker> createState() => _SymptomsPickerState();
}

class _SymptomsPickerState extends State<_SymptomsPicker> {
  final _tc = TextEditingController();

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final ok = await widget.ctrl.addCustomSymptom(_tc.text);
    if (ok) _tc.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── أشهر 20 عرض (Chips بتشيك بوكس) ────────────────────────────
        Obx(() {
          final selected = c.selectedSymptoms.map((e) => e.toLowerCase()).toSet();
          return Wrap(
            spacing: 8,
            runSpacing: 6,
            children: c.topSymptoms.map((name) {
              final sel = selected.contains(name.toLowerCase());
              return FilterChip(
                label: Text(name,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Colors.black)),
                selected: sel,
                showCheckmark: true,
                onSelected: (v) => c.toggleSymptom(name, v),
                selectedColor: AppColors.primary.withOpacity(0.15),
                checkmarkColor: AppColors.primary,
              );
            }).toList(),
          );
        }),
        const SizedBox(height: 14),

        // ── بحث / إضافة عرض ─────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tc,
                textDirection: TextDirection.ltr,
                onChanged: c.searchSymptom,
                onSubmitted: (_) => _add(),
                decoration: const InputDecoration(
                  hintText: 'ابحث أو أضف عرض (English)...',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              tooltip: 'إضافة عرض',
            ),
          ],
        ),

        // رسالة التحقق
        Obx(() => c.symptomHint.value.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(c.symptomHint.value,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.warning)),
              )),

        // اقتراحات البحث من القاموس
        Obx(() {
          if (c.symptomSuggestions.isEmpty) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: c.symptomSuggestions
                  .map((name) => ListTile(
                        dense: true,
                        title: Text(name,
                            style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 13)),
                        trailing: const Icon(Icons.add_circle_outline,
                            size: 18, color: AppColors.primary),
                        onTap: () {
                          c.toggleSymptom(name, true);
                          c.symptomSuggestions.clear();
                          _tc.clear();
                        },
                      ))
                  .toList(),
            ),
          );
        }),

        // الأعراض المختارة اللي مش ضمن الـ 20 (بحث أو إضافة يدوية)
        Obx(() {
          final top = c.topSymptoms.map((e) => e.toLowerCase()).toSet();
          final extra = c.selectedSymptoms
              .where((s) => !top.contains(s.toLowerCase()))
              .toList();
          if (extra.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: extra.map((s) {
                final custom = c.customSymptoms.contains(s);
                return Chip(
                  label: Text(custom ? '$s ✎' : s,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.black)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                  onDeleted: () => c.toggleSymptom(s, false),
                  backgroundColor: AppColors.primary.withOpacity(0.08),
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// أزرار اختصار للتشخيصات/الأمراض المزمنة الأهم لسن المريض (مرتبة بالأولوية)
class DxShortcutChips extends StatelessWidget {
  final AddPatientController ctrl;
  final bool comorbidity;
  const DxShortcutChips(
      {super.key, required this.ctrl, required this.comorbidity});

  @override
  Widget build(BuildContext context) => Obx(() {
        final items =
            comorbidity ? ctrl.comorbidityShortcuts : ctrl.diagnosisShortcuts;
        final selected =
            comorbidity ? ctrl.selectedComorbidities : ctrl.finalDiagnoses;
        ctrl.resolvedShortcuts.length; // اشتراك في تحديث الربط
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: items.map((s) {
            final sel = ctrl.isShortcutSelected(s, selected);
            return FilterChip(
              label: Text(s.label,
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontSize: 12, color: Colors.black)),
              selected: sel,
              onSelected: (_) => comorbidity
                  ? ctrl.toggleComorbidityShortcut(s)
                  : ctrl.toggleDiagnosisShortcut(s),
              selectedColor: AppColors.primary.withOpacity(0.15),
              checkmarkColor: AppColors.primary,
            );
          }).toList(),
        );
      });
}

class DiagnosisSearch extends StatefulWidget {
  final AddPatientController ctrl;
  final void Function(int id, String name) onSelect;
  final String? hint;
  /// لو اتحدد → بحث الأمراض المزمنة (نتايج ونص منفصل عن التشخيص النهائي)
  final bool comorbidity;
  const DiagnosisSearch(
      {super.key,
      required this.ctrl,
      required this.onSelect,
      this.hint,
      this.comorbidity = false});
  @override
  State<DiagnosisSearch> createState() => DiagnosisSearchState();
}

class DiagnosisSearchState extends State<DiagnosisSearch> {
  final _tc = TextEditingController();
  final _listScroll = ScrollController();
  RxList<Map<String, dynamic>> get _results => widget.comorbidity
      ? widget.ctrl.comorbSearchResults
      : widget.ctrl.diagSearchResults;
  RxBool get _loading => widget.comorbidity
      ? widget.ctrl.comorbSearchLoading
      : widget.ctrl.diagSearchLoading;
  @override
  void dispose() {
    _tc.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextField(
            controller: _tc,
            textDirection: TextDirection.rtl,
            onChanged: widget.comorbidity
                ? widget.ctrl.searchComorbidity
                : widget.ctrl.searchDiagnosis,
            decoration: InputDecoration(
              hintText: widget.hint ?? 'ابحث عن التشخيص...',
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          Obx(() {
            if (_loading.value) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            if (_results.isEmpty)
              return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06), blurRadius: 6)
                ],
              ),
              // 3 تشخيصات ظاهرة (48px للصف + فاصلين) والباقي بالسكرول
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 146),
                child: Scrollbar(
                controller: _listScroll,
                thumbVisibility: _results.length > 3,
                child: ListView.separated(
                controller: _listScroll,
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final d = _results[i];
                  return ListTile(
                    dense: true,
                    title: Text(d['name'] as String,
                        style:
                            const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                    trailing: d['icd10'] != null
                        ? Text(d['icd10'] as String,
                            style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppColors.textSecond))
                        : null,
                    onTap: () {
                      widget.onSelect(d['id'] as int, d['name'] as String);
                      _tc.clear();
                      _results.clear();
                    },
                  );
                },
              ),
              ),
              ),
            );
          }),
        ],
      );
}

class DiagnosisTags extends StatelessWidget {
  final List<String> items;
  final void Function(String) onRemove;
  final Color color;
  const DiagnosisTags(
      {super.key,
      required this.items,
      required this.onRemove,
      required this.color});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: items
            .map((d) => Chip(
                  label: Text(d,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.black)),
                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                  onDeleted: () => onRemove(d),
                  backgroundColor: color.withOpacity(0.08),
                  side: BorderSide(color: color.withOpacity(0.3)),
                  deleteIconColor: color,
                ))
            .toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  STEP 3 — التاريخ الطبي (الأسئلة الثلاثة)
// ─────────────────────────────────────────────────────────────────────────────
class _Step3Medical extends StatelessWidget {
  final AddPatientController ctrl;
  const _Step3Medical({required this.ctrl});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── سؤال ١: أمراض مزمنة؟ ──────────────────────────────────────
            _YesNoCard(
              question: 'هل يعاني المريض من أمراض مزمنة؟',
              icon: Icons.medical_services_outlined,
              value: ctrl.hasComorbidities,
              onChanged: (v) {
                ctrl.hasComorbidities.value = v;
                if (!v) ctrl.selectedComorbidities.clear();
              },
              child: Obx(() {
                if (!ctrl.hasComorbidities.value)
                  return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    const Text('الأشهر لسن المريض:',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    DxShortcutChips(ctrl: ctrl, comorbidity: true),
                    const SizedBox(height: 12),
                    DiagnosisSearch(
                      ctrl: ctrl,
                      comorbidity: true,
                      onSelect: (id, name) => ctrl.addComorbidity(name),
                      hint: 'ابحث عن مرض مزمن...',
                    ),
                    Obx(() => DiagnosisTags(
                          items: ctrl.selectedComorbidities.toList(),
                          onRemove: ctrl.removeComorbidity,
                          color: AppColors.primary,
                        )),
                  ],
                );
              }),
            ),
            const SizedBox(height: 16),

            // ── سؤال ٢: أدوية مزمنة؟ ──────────────────────────────────────
            _YesNoCard(
              question: 'هل يأخذ المريض أدوية بشكل منتظم؟',
              icon: Icons.medication_outlined,
              value: ctrl.hasChronicMeds,
              onChanged: (v) {
                ctrl.hasChronicMeds.value = v;
                if (!v) ctrl.chronicMeds.clear();
              },
              child: Obx(() {
                if (!ctrl.hasChronicMeds.value) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: DrugPickerWidget(ctrl: ctrl, isChronic: true),
                );
              }),
            ),
            const SizedBox(height: 16),

            // ── سؤال ٣: حساسية؟ ────────────────────────────────────────────
            _YesNoCard(
              question: 'هل لدى المريض حساسية من أدوية؟',
              icon: Icons.warning_amber_outlined,
              value: ctrl.hasAllergies,
              onChanged: (v) {
                ctrl.hasAllergies.value = v;
                if (!v) ctrl.allergies.clear();
              },
              child: Obx(() {
                if (!ctrl.hasAllergies.value) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _AllergyAdder(ctrl: ctrl),
                );
              }),
            ),
            const SizedBox(height: 16),

            // ── سؤال ٤: أعشاب أو مكملات؟ ───────────────────────────────────
            _YesNoCard(
              question: 'هل المريض بياخد أعشاب أو مكملات عشبية؟',
              icon: Icons.eco_outlined,
              value: ctrl.hasHerbs,
              onChanged: (v) {
                ctrl.hasHerbs.value = v;
                if (!v) ctrl.selectedHerbs.clear();
              },
              child: Obx(() {
                if (!ctrl.hasHerbs.value) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _HerbPicker(ctrl: ctrl),
                );
              }),
            ),

            const SizedBox(height: 32),
            _NavButtons(ctrl: ctrl, isLast: false),
          ],
        ),
      );
}

class _YesNoCard extends StatelessWidget {
  final String question;
  final IconData icon;
  final RxBool value;
  final void Function(bool) onChanged;
  final Widget child;
  const _YesNoCard({
    required this.question,
    required this.icon,
    required this.value,
    required this.onChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(question,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                  Obx(() => Switch.adaptive(
                        value: value.value,
                        onChanged: onChanged,
                        activeColor: AppColors.primary,
                      )),
                ],
              ),
            ),
            Obx(() => AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: child,
                  ),
                  crossFadeState: value.value
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                )),
          ],
        ),
      );
}

class _AllergyAdder extends StatefulWidget {
  final AddPatientController ctrl;
  const _AllergyAdder({required this.ctrl});
  @override
  State<_AllergyAdder> createState() => _AllergyAdderState();
}

class _AllergyAdderState extends State<_AllergyAdder> {
  final _searchCtrl = TextEditingController();
  DrugSearchResult? _selectedDrug;
  String? _detectedClass;
  String _scope = 'drug'; // 'drug' | 'class'
  String _reactionType = kAllergyTypes.first;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _pickDrug(DrugSearchResult d) {
    setState(() {
      _selectedDrug = d;
      _detectedClass = firstKnownClassFor(d.genericTokens);
      _scope = 'drug';
    });
    widget.ctrl.allergyDrugResults.clear();
  }

  void _clearSelection() {
    setState(() {
      _selectedDrug = null;
      _detectedClass = null;
      _scope = 'drug';
    });
    _searchCtrl.clear();
  }

  void _add() {
    final d = _selectedDrug;
    if (d == null) return;
    final tokens = d.genericTokens;
    final scopeTokens = (_scope == 'class' && _detectedClass != null)
        ? tokens.expand(tokensInSameClass).toSet().toList()
        : tokens;
    final label = (_scope == 'class' && _detectedClass != null)
        ? _detectedClass!
        : d.brandName;
    widget.ctrl.addAllergy(
      label: label,
      reactionType: _reactionType,
      scopeTokens: scopeTokens,
      className: (_scope == 'class') ? _detectedClass : null,
    );
    _clearSelection();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── حقل البحث عن الدواء المسبب للحساسية ────────────────────────
          if (_selectedDrug == null) ...[
            TextField(
              controller: _searchCtrl,
              onChanged: widget.ctrl.searchAllergyDrug,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                hintText: 'ابحث عن الدواء المسبب للحساسية (Augmentin...)',
                prefixIcon: Icon(Icons.medication_outlined, size: 18),
              ),
            ),
            Obx(() {
              final results = widget.ctrl.allergyDrugResults;
              if (results.isEmpty) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06), blurRadius: 6)
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = results[i];
                    return ListTile(
                      dense: true,
                      title: Text(d.brandName,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      subtitle: Text(d.genericName,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: AppColors.textSecond)),
                      trailing: Text(d.strength,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: AppColors.primary)),
                      onTap: () => _pickDrug(d),
                    );
                  },
                ),
              );
            }),
          ],

          // ── بطاقة الدواء المختار + اختيار النطاق ───────────────────────
          if (_selectedDrug != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_selectedDrug!.brandName} (${_selectedDrug!.genericName})',
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: _clearSelection,
                        tooltip: 'إلغاء الاختيار',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_detectedClass != null) ...[
                    Row(
                      children: [
                        const Icon(Icons.category_outlined,
                            size: 15, color: AppColors.warning),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('عيلة الدواء: $_detectedClass',
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warning)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('الحساسية من ${_selectedDrug!.brandName} بس',
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 12)),
                      value: 'drug',
                      groupValue: _scope,
                      onChanged: (v) => setState(() => _scope = v!),
                    ),
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('الحساسية من عيلة $_detectedClass كاملة',
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 12)),
                      value: 'class',
                      groupValue: _scope,
                      onChanged: (v) => setState(() => _scope = v!),
                    ),
                  ] else
                    const Text(
                        'المادة الفعالة دي مش مصنّفة ضمن عيلة معروفة في القاعدة حاليًا — هتتسجّل الحساسية للدواء ده بس.',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: AppColors.textSecond)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _reactionType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'نوع رد الفعل', isDense: true),
                    items: kAllergyTypes
                        .map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(t,
                                style: const TextStyle(
                                    fontFamily: 'Cairo', fontSize: 12))))
                        .toList(),
                    onChanged: (v) => setState(() => _reactionType = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('إضافة حساسية'),
              ),
            ),
          ],

          // ── قايمة الحساسيات المضافة ─────────────────────────────────────
          Obx(() => Column(
                children: widget.ctrl.allergies.asMap().entries.map((e) {
                  final a = e.value;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warning_amber_rounded,
                        color: AppColors.warning, size: 18),
                    title: Row(
                      children: [
                        Flexible(
                            child: Text(a.drugName,
                                style: const TextStyle(
                                    fontFamily: 'Cairo', fontSize: 13))),
                        if (a.className != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('عيلة كاملة',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 9,
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(a.reactionType,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: AppColors.textSecond)),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline_rounded,
                          color: AppColors.danger, size: 18),
                      onPressed: () => widget.ctrl.removeAllergy(e.key),
                    ),
                  );
                }).toList(),
              )),
        ],
      );
}

// ── Herb Picker (chips من الـ 22 عشب الموجودين في القاعدة) ────────────────────
class _HerbPicker extends StatelessWidget {
  final AddPatientController ctrl;
  const _HerbPicker({required this.ctrl});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('اختار العشب/العشبين اللي المريض بياخدهم:',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecond)),
          const SizedBox(height: 8),
          Obx(() {
            if (ctrl.allHerbs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            return Wrap(
              spacing: 8,
              runSpacing: 6,
              children: ctrl.allHerbs.map((h) {
                final sel = ctrl.selectedHerbs.contains(h);
                return FilterChip(
                  label: Text(h,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: Colors.black)),
                  selected: sel,
                  onSelected: (_) => ctrl.toggleHerb(h),
                  selectedColor: AppColors.success.withOpacity(0.15),
                  checkmarkColor: AppColors.success,
                );
              }).toList(),
            );
          }),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  STEP 4 — الأدوية الموصوفة
// ─────────────────────────────────────────────────────────────────────────────
class _Step4Medications extends StatelessWidget {
  final AddPatientController ctrl;
  const _Step4Medications({required this.ctrl});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader('الأدوية الموصوفة'),
            const Text(
              'أضف الأدوية التي وصفها الطبيب',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: AppColors.textSecond),
            ),
            const SizedBox(height: 16),
            DrugPickerWidget(ctrl: ctrl, isChronic: false),
            FluidSection(ctrl: ctrl),
            _LabsPreviewCard(ctrl: ctrl),
            const SizedBox(height: 32),

            // ── زر الحفظ ────────────────────────────────────────────────
            Obx(() => SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: ctrl.isSaving.value ? null : ctrl.save,
                    icon: ctrl.isSaving.value
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                        ctrl.isSaving.value ? 'جاري الحفظ...' : 'حفظ المريض'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      textStyle: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                )),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: ctrl.prevStep,
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                label: const Text('السابق'),
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  معاينة التحاليل المطلوبة (من التشخيص النهائي + الأدوية المضافة)
// ─────────────────────────────────────────────────────────────────────────────
class _LabsPreviewCard extends StatelessWidget {
  final AddPatientController ctrl;
  const _LabsPreviewCard({required this.ctrl});

  @override
  Widget build(BuildContext context) => Obx(() {
        final labs = ctrl.previewLabs;
        if (labs.isEmpty) return const SizedBox.shrink();
        final ess = labs.where((l) => l.priority == 'essential').toList();
        final rest = labs.where((l) => l.priority != 'essential').toList();

        Widget row(RecommendedLab l) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${l.drugs.isNotEmpty ? '💊 ' : ''}${l.lab.shortName == l.lab.name ? l.lab.name : '${l.lab.name} (${l.lab.shortName})'}'
                      '${l.frequency.isEmpty ? '' : ' — ${l.frequency}'}',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  if (l.rationales.isNotEmpty)
                    Text(l.rationales.first,
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: AppColors.textSecond)),
                ],
              ),
            );

        return Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.info.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🧪 التحاليل المطلوبة للمتابعة (${labs.length})',
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const SizedBox(height: 2),
              const Text('تقدر تسجّل نتايجها من تبويب "التحاليل" في ملف المريض بعد الحفظ.',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: AppColors.textSecond)),
              const SizedBox(height: 6),
              ...ess.map(row),
              if (rest.isNotEmpty)
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text('تحاليل أخرى (${rest.length})',
                        style: const TextStyle(
                            fontFamily: 'Cairo', fontSize: 12)),
                    children: rest.map(row).toList(),
                  ),
                ),
            ],
          ),
        );
      });
}

// ─────────────────────────────────────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      );
}

class _NavButtons extends StatelessWidget {
  final AddPatientController ctrl;
  final bool isLast;
  const _NavButtons({required this.ctrl, required this.isLast});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Obx(() => ctrl.currentStep.value > 0
              ? Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: OutlinedButton.icon(
                      onPressed: ctrl.prevStep,
                      icon:
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                      label: const Text('السابق'),
                    ),
                  ),
                )
              : const SizedBox.shrink()),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: ctrl.nextStep,
              icon: const Icon(Icons.arrow_back_ios_rounded, size: 14),
              label: const Text('التالي'),
            ),
          ),
        ],
      );
}
