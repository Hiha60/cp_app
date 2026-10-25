import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/iv_fluids.dart';
import '../controllers/add_patient_controller.dart';
import '../../../data/models/patient_model.dart';
import '../../../core/services/local_db_service.dart';

/// قسم المحاليل الوريدية — يوضع داخل _Step4Medications بعد DrugPickerWidget
/// الاستخدام:  FluidSection(ctrl: ctrl)
class FluidSection extends StatefulWidget {
  final AddPatientController ctrl;
  const FluidSection({super.key, required this.ctrl});
  @override
  State<FluidSection> createState() => _FluidSectionState();
}

class _FluidSectionState extends State<FluidSection> {
  bool _showDexSalt = false;
  bool _showOther = false;
  String? _otherGroup;

  AddPatientController get c => widget.ctrl;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 32),
          Obx(() => SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('المريض أخد محاليل وريدية؟',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                value: c.tookFluids.value,
                onChanged: (v) {
                  c.tookFluids.value = v;
                  if (!v) {
                    c.fluidOrders.clear();
                    c.cancelDraftFluid();
                  }
                },
              )),
          Obx(() {
            if (!c.tookFluids.value) return const SizedBox.shrink();
            final draft = c.draftFluid.value;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (draft == null) _picker() else _additivePanel(draft),
              if (c.fluidOrders.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (var i = 0; i < c.fluidOrders.length; i++) _orderTile(i),
              ],
            ]);
          }),
        ],
      );

  // ── اختيار المحلول: 4 واضحين + أخرى ─────────────────────────────────
  Widget _picker() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('اختر المحلول',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          ...kMainFluids.map((f) => _chip(f.name.split(' (').first, false, () => c.startFluid(f))),
          _chip('محلول جلوكوز ملحي', _showDexSalt, () => setState(() {
                _showDexSalt = !_showDexSalt;
                _showOther = false;
              })),
          _chip('أخرى', _showOther, () => setState(() {
                _showOther = !_showOther;
                _showDexSalt = false;
              })),
        ]),
        if (_showDexSalt) ...[
          const SizedBox(height: 10),
          _fluidWrap(fluidsOfGroup('dexsalt')),
        ],
        if (_showOther) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final g in kOtherGroups)
              _chip(kFluidGroupTitles[g]!, _otherGroup == g,
                  () => setState(() => _otherGroup = _otherGroup == g ? null : g)),
          ]),
          if (_otherGroup != null) ...[
            const SizedBox(height: 10),
            // الأربعة الواضحين مش بيتكرروا تحت "أخرى"
            _fluidWrap(fluidsOfGroup(_otherGroup!).where((f) => !f.main).toList()),
            if (_otherGroup == 'albumin')
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('الأسماء التجارية: ${kAlbuminBrands.join('، ')}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: AppColors.textSecond)),
              ),
          ],
        ],
      ]);

  Widget _fluidWrap(List<FluidDef> list) => Wrap(spacing: 8, runSpacing: 6, children: [
        for (final f in list) _chip(f.name, false, () => c.startFluid(f)),
      ]);

  // ── بعد اختيار المحلول: الأمبولات/الفيالات ───────────────────────────
  Widget _additivePanel(FluidDef f) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.info.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.info.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.water_drop_rounded, color: AppColors.info, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(f.name, style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700))),
            IconButton(icon: const Icon(Icons.close_rounded), onPressed: c.cancelDraftFluid),
          ]),
          const SizedBox(height: 4),
          const Text('أمبول / فيال مضاف على المحلول (اختياري) — تظهر الأمبولات والفيالات فقط',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: AppColors.textSecond)),
          const SizedBox(height: 10),
          _AdditivePicker(ctrl: c),
          Obx(() => Column(children: [
                for (var i = 0; i < c.draftAdditives.length; i++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                        c.draftAdditives[i].ivWarning != null
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline_rounded,
                        color: c.draftAdditives[i].ivWarning != null ? AppColors.warning : AppColors.success,
                        size: 20),
                    title: Text(
                        '${c.draftAdditives[i].med.brandName} ${c.draftAdditives[i].med.strength} — ${c.draftAdditives[i].med.form}',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                    trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger, size: 20),
                        onPressed: () => c.removeDraftAdditive(i)),
                  ),
              ])),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: c.confirmFluid,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('تأكيد المحلول'),
            ),
          ),
        ]),
      );

  Widget _orderTile(int i) {
    final o = c.fluidOrders[i];
    return Card(
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.water_drop_rounded, color: AppColors.info),
        title: Text(o.name, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: o.additives.isEmpty
            ? null
            : Text(
                o.additives
                    .map((a) => '${a.med.brandName} ${a.med.strength}${a.ivWarning != null ? ' ⚠️' : ''}')
                    .join(' + '),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
        trailing: IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.danger, size: 20),
            onPressed: () => c.removeFluid(i)),
      ),
    );
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary.withOpacity(0.12) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? AppColors.primary : Colors.grey.shade300),
          ),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12.5,
                  color: sel ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.normal)),
        ),
      );
}


// ── بحث أمبولات/فيالات فقط + اختيار التركيز/الشكل + زر الإضافة ──────────────
class _AdditivePicker extends StatefulWidget {
  final AddPatientController ctrl;
  const _AdditivePicker({required this.ctrl});
  @override
  State<_AdditivePicker> createState() => _AdditivePickerState();
}

class _AdditivePickerState extends State<_AdditivePicker> {
  final _tc = TextEditingController();
  AddPatientController get c => widget.ctrl;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _tc,
            onChanged: c.searchFluidDrug,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              hintText: 'ابحث عن أمبول / فيال...',
              prefixIcon: const Icon(Icons.vaccines_outlined),
              suffixIcon: Obx(() => c.fluidDrug.value != null
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _tc.clear();
                        c.resetFluidPicker();
                      })
                  : const SizedBox.shrink()),
            ),
          ),
          Obx(() {
            if (c.fluidDrugResults.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: c.fluidDrugResults.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final d = c.fluidDrugResults[i];
                  return ListTile(
                    dense: true,
                    title: Text(d.brandName,
                        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black)),
                    subtitle: Text(d.genericName,
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.black)),
                    onTap: () {
                      _tc.text = d.brandName;
                      c.selectFluidDrug(d);
                    },
                  );
                },
              ),
            );
          }),
          Obx(() {
            if (c.fluidVariantLabels.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(spacing: 8, runSpacing: 6, children: [
                for (final l in c.fluidVariantLabels)
                  GestureDetector(
                    onTap: () => c.selectFluidVariant(l),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.fluidSelectedLabel.value == l
                            ? AppColors.primary.withOpacity(0.12)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: c.fluidSelectedLabel.value == l
                                ? AppColors.primary
                                : Colors.grey.shade300),
                      ),
                      child: Text(l,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: Colors.black,
                              fontWeight: c.fluidSelectedLabel.value == l
                                  ? FontWeight.w700
                                  : FontWeight.normal)),
                    ),
                  ),
              ]),
            );
          }),
          Obx(() {
            final s = c.fluidSelected.value;
            if (s == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('المختار: ${s.brandName}  •  ${c.fluidSelectedLabel.value}',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black)),
            );
          }),
          const SizedBox(height: 10),
          Obx(() => SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: c.canAddAdditive
                      ? () async {
                          await c.addFluidAdditive();
                          _tc.clear();
                        }
                      : null,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('إضافة على المحلول'),
                ),
              )),
        ],
      );
}
