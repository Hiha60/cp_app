import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/alert_engine.dart';
import '../../../core/services/local_db_service.dart';
import '../controllers/add_patient_controller.dart';
import '../../../data/models/patient_model.dart';

class DrugPickerWidget extends StatelessWidget {
  final AddPatientController ctrl;
  final bool isChronic;
  const DrugPickerWidget({super.key, required this.ctrl, this.isChronic = false});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ── خطوة ١: البحث عن الدواء ────────────────────────────────────
      _StepLabel(step: '١', label: 'ابحث عن الدواء'),
      const SizedBox(height: 8),
      _DrugSearchField(ctrl: ctrl),

      // ── خطوة ٢: اختيار الصنف (التركيز + الشكل الصيدلي مع بعض) ──────
      //    بتظهر بس لو البراند له أكتر من صنف؛ غير كده بيتحدد تلقائي
      Obx(() {
        if (ctrl.drugStrengths.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _StepLabel(step: '٢', label: 'اختر التركيز والشكل الصيدلي'),
            const SizedBox(height: 8),
            _ChipsRow(
              items:    ctrl.drugStrengths,
              selected: ctrl.selectedStrengthLabel,
              onTap:    ctrl.selectStrengthChoice,
            ),
          ],
        );
      }),

      // ── ملخص الصنف المحدد + التكرار (بيظهر لما يتحدد الصنف بالكامل) ──
      Obx(() {
        final s = ctrl.selectedStrength.value;
        if (s == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.success.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${s.brandName}${ctrl.selectedStrengthLabel.value.isEmpty ? '' : '  •  ${ctrl.selectedStrengthLabel.value}'}',
                      style: const TextStyle(fontFamily:'Cairo', fontSize:13, fontWeight:FontWeight.w600, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _StepLabel(step: '', label: 'التكرار'),
            const SizedBox(height: 8),
            _ChipsRow(
              items:    kFrequencies,
              selected: ctrl.selectedFrequency,
              onTap:    ctrl.selectFrequency,
            ),
            DoseQtyChips(ctrl: ctrl),
          ],
        );
      }),

      // ── زر الإضافة ──────────────────────────────────────────────────
      const SizedBox(height: 16),
      Obx(() => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: ctrl.canAddMed
              ? (isChronic ? ctrl.addChronicMed : ctrl.addPrescribedMed)
              : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(isChronic ? 'إضافة للأدوية المزمنة' : 'إضافة للأدوية الموصوفة'),
        ),
      )),

      // ── معاينة ما تمت إضافته ─────────────────────────────────────────
      Obx(() {
        final list = isChronic ? ctrl.chronicMeds : ctrl.prescribedMeds;
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            const SizedBox(height: 16),
            const Divider(),
            ...list.asMap().entries.map((e) => _MedTile(
              med:      e.value,
              onRemove: () => isChronic
                  ? ctrl.removeChronicMed(e.key)
                  : ctrl.removePrescribedMed(e.key),
            )),
          ],
        );
      }),
    ],
  );
}

// ── عدد الأقراص / المل في الجرعة (اختياري) ───────────────────────────────────
// بيظهر بس لو الدواء قابل للحساب الرقمي (قرص/كبسولة/أمبولة/شراب بتركيز mg).
// شراب من غير ما تحدد المل = التنبيه الرقمي للجرعة مش هيتفحص.
class DoseQtyChips extends StatelessWidget {
  final AddPatientController ctrl;
  const DoseQtyChips({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) => Obx(() {
    final s = ctrl.selectedStrength.value;
    if (s == null) return const SizedBox.shrink();
    final opts = doseQtyOptionsFor(
        strength: s.strength, form: s.form, brandName: s.brandName);
    if (opts == null) return const SizedBox.shrink();
    final sel = ctrl.selectedDoseQty.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _StepLabel(
            step: '',
            label: opts.isMl ? 'المل في الجرعة' : 'عدد الأقراص/الوحدات في الجرعة'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: opts.values.map((v) {
            final on = sel == v;
            return GestureDetector(
              onTap: () => ctrl.selectDoseQty(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: on ? AppColors.primary.withOpacity(0.12) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: on ? AppColors.primary : Colors.grey.shade300),
                ),
                child: Text(
                  opts.isMl ? '${fmtQty(v)} مل' : fmtQty(v),
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: Colors.black,
                    fontWeight: on ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (opts.isMl && sel == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('حدّد المل عشان يتفحص حد الجرعة اليومية',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.black54)),
          )
        else if (!opts.isMl && sel == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('لو ما اتحددش هنفترض وحدة واحدة في الجرعة',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.black54)),
          ),
      ],
    );
  });
}

// ── Drug Search Field ─────────────────────────────────────────────────────────
class _DrugSearchField extends StatefulWidget {
  final AddPatientController ctrl;
  const _DrugSearchField({required this.ctrl});
  @override State<_DrugSearchField> createState() => _DrugSearchFieldState();
}

class _DrugSearchFieldState extends State<_DrugSearchField> {
  final _textCtrl = TextEditingController();

  @override
  void dispose() { _textCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        controller: _textCtrl,
        onChanged: widget.ctrl.searchDrug,
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          hintText: 'Augmentin, Amoxil...',
          prefixIcon: const Icon(Icons.medication_outlined),
          suffixIcon: Obx(() => widget.ctrl.selectedDrug.value != null
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () {
                    _textCtrl.clear();
                    widget.ctrl.searchDrug('');
                    widget.ctrl.resetDrugSelection();
                  },
                )
              : const SizedBox.shrink()),
        ),
      ),
      // Dropdown نتائج البحث
      Obx(() {
        if (widget.ctrl.drugSearchResults.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0,4))],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: widget.ctrl.drugSearchResults.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = widget.ctrl.drugSearchResults[i];
              return ListTile(
                dense: true,
                title: Text(d.brandName, style: const TextStyle(fontFamily:'Cairo', fontWeight:FontWeight.w600, fontSize:14, color: Colors.black)),
                subtitle: Text(d.genericName, style: const TextStyle(fontFamily:'Cairo', fontSize:12, color: Colors.black)),
                trailing: const Icon(Icons.chevron_left_rounded, size: 18, color: Colors.black),
                onTap: () {
                  _textCtrl.text = d.brandName;
                  widget.ctrl.selectDrug(d);
                },
              );
            },
          ),
        );
      }),
    ],
  );
}

// ── Generic Chips Row ─────────────────────────────────────────────────────────
class _ChipsRow extends StatelessWidget {
  final List<String> items;
  final RxString selected;
  final void Function(String) onTap;
  const _ChipsRow({required this.items, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Obx(() => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: items.map((item) {
      final sel = selected.value == item;
      return GestureDetector(
        onTap: () => onTap(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary.withOpacity(0.12) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? AppColors.primary : Colors.grey.shade300),
          ),
          child: Text(
            item,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: Colors.black,
              fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
      );
    }).toList(),
  ));
}

// ── Med Tile (قائمة الأدوية المضافة) ─────────────────────────────────────────
class _MedTile extends StatelessWidget {
  final MedicationModel med;
  final VoidCallback onRemove;
  const _MedTile({required this.med, required this.onRemove});

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: const Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 20),
    title: Text(med.displayText, style: const TextStyle(fontFamily:'Cairo', fontSize:13, color: Colors.black)),
    trailing: IconButton(
      icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger, size: 20),
      onPressed: onRemove,
    ),
  );
}

// ── Step Label ────────────────────────────────────────────────────────────────
class _StepLabel extends StatelessWidget {
  final String step, label;
  const _StepLabel({required this.step, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (step.isNotEmpty) ...[
        Container(
          width: 22, height: 22,
          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(step, style: const TextStyle(fontFamily:'Cairo', color:Colors.white, fontSize:11, fontWeight:FontWeight.w700)),
        ),
        const SizedBox(width: 8),
      ],
      Text(label, style: const TextStyle(fontFamily:'Cairo', fontSize:13, fontWeight:FontWeight.w600, color: Colors.black)),
    ],
  );
}
