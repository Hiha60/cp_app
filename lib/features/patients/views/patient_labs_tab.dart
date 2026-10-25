import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/local_db_service.dart';
import '../../../data/models/patient_model.dart';
import '../../auth/controllers/auth_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  تبويب التحاليل في ملف المريض
//  • التحاليل المقترحة من تشخيصات المريض (مجمّعة حسب الأولوية) مع السبب/التكرار/الهدف
//  • آخر نتيجة + المدى الطبيعي حسب سن/جنس المريض + لون الحالة
//  • إضافة نتيجة (رقمي/نوعي) + إضافة أي تحليل آخر بالبحث + حذف نتيجة خاطئة
//  الـ widget ده مفيهوش منطق تخزين: بيستدعي onAdd/onRemove من الـ controller.
// ─────────────────────────────────────────────────────────────────────────────
class PatientLabsTab extends StatelessWidget {
  final PatientModel patient;
  final List<RecommendedLab> recommended;
  final Map<String, LabRange?> ranges;
  final Map<String, LabTest> labTests;
  final Future<void> Function(LabResultModel) onAdd;
  final Future<void> Function(LabResultModel) onRemove;

  const PatientLabsTab({
    super.key,
    required this.patient,
    required this.recommended,
    required this.ranges,
    required this.labTests,
    required this.onAdd,
    required this.onRemove,
  });

  List<LabResultModel> _resultsFor(String code) => patient.labResults
      .where((r) => r.labCode == code)
      .toList()
    ..sort((a, b) => b.takenAt.compareTo(a.takenAt));

  @override
  Widget build(BuildContext context) {
    final recCodes = recommended.map((r) => r.lab.code).toSet();
    final otherCodes = patient.labResults
        .map((r) => r.labCode)
        .where((c) => !recCodes.contains(c))
        .toSet()
        .toList();

    Widget group(String title, String priority, Color color,
        {bool collapsed = false}) {
      final items = recommended.where((r) => r.priority == priority).toList();
      if (items.isEmpty) return const SizedBox.shrink();
      final cards = items
          .map((r) => _LabCard(
                lab: r.lab,
                rec: r,
                range: ranges[r.lab.code],
                results: _resultsFor(r.lab.code),
                patient: patient,
                onAdd: onAdd,
                onRemove: onRemove,
              ))
          .toList();
      final header = Text('$title (${items.length})',
          style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: color));
      if (collapsed) {
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: header,
            children: cards,
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 8), ...cards],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (patient.sex == null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
            ),
            child: const Text(
              'جنس المريض غير مسجّل — النسب الطبيعية المعروضة بتشمل الذكور والإناث '
              '(وبعض التنبيهات، زي حساب CrCl، مش هتشتغل).',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 12),
            ),
          ),
        if (recommended.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'مفيش تحاليل مقترحة لتشخيصات المريض الحالية. تقدر تضيف أي تحليل يدوياً.',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  color: AppColors.textSecond),
            ),
          ),
        group('تحاليل أساسية', 'essential', AppColors.danger),
        const SizedBox(height: 12),
        group('تحاليل مهمة', 'important', AppColors.primary),
        const SizedBox(height: 12),
        group('تحاليل اختيارية', 'optional', AppColors.textSecond,
            collapsed: true),
        if (otherCodes.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('نتائج أخرى',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: AppColors.textSecond)),
          const SizedBox(height: 8),
          ...otherCodes.map((c) {
            final res = _resultsFor(c);
            final lab = labTests[c] ??
                LabTest(
                    id: 0,
                    code: c,
                    name: res.first.labName,
                    unit: res.first.unit);
            return _LabCard(
              lab: lab,
              rec: null,
              range: ranges[c],
              results: res,
              patient: patient,
              onAdd: onAdd,
              onRemove: onRemove,
            );
          }),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _pickAnyLab(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('إضافة تحليل آخر'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _pickAnyLab(BuildContext context) async {
    final lab = await showDialog<LabTest>(
      context: context,
      builder: (_) => const _LabSearchDialog(),
    );
    if (lab == null || !context.mounted) return;
    final range = await LocalDbService.instance.getReferenceRange(lab.code,
        age: patient.age, sex: patient.sex, isPregnant: patient.isPregnant);
    if (!context.mounted) return;
    await showAddLabResultDialog(
        context: context, lab: lab, range: range, onAdd: onAdd);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
Color _statusColor(LabStatus s) => switch (s) {
      LabStatus.normal => AppColors.success,
      LabStatus.low || LabStatus.high => AppColors.warning,
      LabStatus.criticalLow || LabStatus.criticalHigh => AppColors.danger,
      LabStatus.unknown => AppColors.textSecond,
    };

String _statusText(LabStatus s) => switch (s) {
      LabStatus.normal => 'طبيعي',
      LabStatus.low => 'منخفض',
      LabStatus.high => 'مرتفع',
      LabStatus.criticalLow => 'منخفض جداً ⚠️',
      LabStatus.criticalHigh => 'مرتفع جداً ⚠️',
      LabStatus.unknown => '—',
    };

String _fmtVal(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

String _fmtDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

class _LabCard extends StatefulWidget {
  final LabTest lab;
  final RecommendedLab? rec;
  final LabRange? range;
  final List<LabResultModel> results; // الأحدث أولاً
  final PatientModel patient;
  final Future<void> Function(LabResultModel) onAdd;
  final Future<void> Function(LabResultModel) onRemove;
  const _LabCard({
    required this.lab,
    required this.rec,
    required this.range,
    required this.results,
    required this.patient,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  State<_LabCard> createState() => _LabCardState();
}

class _LabCardState extends State<_LabCard> {
  bool _history = false;

  LabStatus _statusOf(LabResultModel r) {
    if (widget.lab.isQualitative) {
      return r.abnormal == true ? LabStatus.high : LabStatus.normal;
    }
    if (r.value == null) return LabStatus.unknown;
    return evaluateLabValue(widget.lab, widget.range, r.value!);
  }

  String _valueText(LabResultModel r) {
    if (widget.lab.isQualitative) {
      return r.abnormal == true ? 'غير طبيعي / إيجابي' : 'طبيعي / سلبي';
    }
    return '${r.value == null ? '—' : _fmtVal(r.value!)} ${r.unit}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    final lab = widget.lab;
    final rec = widget.rec;
    final last = widget.results.isEmpty ? null : widget.results.first;
    final st = last == null ? null : _statusOf(last);
    final range = widget.range;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      lab.shortName == lab.name
                          ? lab.name
                          : '${lab.name} (${lab.shortName})',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
                if (lab.panel != null)
                  Text(lab.panel!,
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10,
                          color: AppColors.textSecond)),
              ],
            ),
            if (rec != null) ...[
              const SizedBox(height: 6),
              if (rec.rationales.isNotEmpty)
                Text(rec.rationales.take(2).join(' • '),
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.textSecond)),
              if (rec.frequency.isNotEmpty)
                Text('التكرار: ${rec.frequency}',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
              if (rec.targets.isNotEmpty)
                Text('الهدف: ${rec.targets.join(' | ')}',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.primary)),
              if (rec.drugs.isNotEmpty)
                Text('💊 للدواء: ${rec.drugs.join('، ')}',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: AppColors.textSecond)),
              if (rec.diagnoses.isNotEmpty)
                Text('للتشخيص: ${rec.diagnoses.join('، ')}',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: AppColors.textSecond)),
            ] else if (lab.noteAr != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(lab.noteAr!,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.textSecond)),
              ),
            if (!lab.isQualitative && range != null && range.isNumeric) ...[
              const SizedBox(height: 6),
              Text(
                  'المدى الطبيعي: ${range.text(lab.unit)}'
                  '${range.sexAssumed ? ' (ذكر/أنثى)' : ''}',
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
              if (range.note != null)
                Text(range.note!,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: AppColors.textSecond)),
            ],
            const Divider(height: 18),
            if (last == null)
              const Text('لا توجد نتيجة مسجّلة',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: AppColors.textSecond))
            else
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(st!).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${_valueText(last)} — ${_statusText(st)}',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _statusColor(st))),
                  ),
                  const SizedBox(width: 8),
                  Text(_fmtDate(last.takenAt),
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: AppColors.textSecond)),
                ],
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => showAddLabResultDialog(
                      context: context,
                      lab: lab,
                      range: range,
                      onAdd: widget.onAdd),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('إضافة نتيجة',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
                const Spacer(),
                if (widget.results.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _history = !_history),
                    child: Text(
                        _history
                            ? 'إخفاء السجل'
                            : 'السجل (${widget.results.length})',
                        style:
                            const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                  ),
              ],
            ),
            if (_history)
              ...widget.results.map((r) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_valueText(r),
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: _statusColor(_statusOf(r)),
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${_fmtDate(r.takenAt)}'
                        '${r.addedByUserName.isEmpty ? '' : ' — ${r.addedByUserName}'}'
                        '${r.note == null || r.note!.isEmpty ? '' : '\n${r.note}'}',
                        style: const TextStyle(
                            fontFamily: 'Cairo', fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 18, color: AppColors.danger),
                      tooltip: 'حذف النتيجة',
                      onPressed: () => _confirmRemove(context, r),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, LabResultModel r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف النتيجة', style: TextStyle(fontFamily: 'Cairo')),
        content: Text('حذف نتيجة ${widget.lab.name} (${_valueText(r)})؟',
            style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.onRemove(r);
    } catch (e) {
      Get.snackbar('تعذّر الحذف', '$e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  بحث تحليل (لإضافة تحليل مش مقترح)
// ─────────────────────────────────────────────────────────────────────────────
class _LabSearchDialog extends StatefulWidget {
  const _LabSearchDialog();
  @override
  State<_LabSearchDialog> createState() => _LabSearchDialogState();
}

class _LabSearchDialogState extends State<_LabSearchDialog> {
  List<LabTest> _results = [];

  Future<void> _search(String q) async {
    final r = await LocalDbService.instance.searchLabs(q);
    if (mounted) setState(() => _results = r);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('إضافة تحليل', style: TextStyle(fontFamily: 'Cairo')),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                textDirection: TextDirection.ltr,
                onChanged: _search,
                decoration: const InputDecoration(
                  hintText: 'ابحث: creatinine, CBC, K, INR...',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: _results
                      .map((l) => ListTile(
                            dense: true,
                            title: Text(l.name,
                                style: const TextStyle(
                                    fontFamily: 'Cairo', fontSize: 13)),
                            subtitle: Text(
                                '${l.shortName}${l.panel == null ? '' : ' — ${l.panel}'}',
                                style: const TextStyle(
                                    fontFamily: 'Cairo', fontSize: 11)),
                            onTap: () => Navigator.pop(context, l),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  إضافة نتيجة
// ─────────────────────────────────────────────────────────────────────────────
Future<void> showAddLabResultDialog({
  required BuildContext context,
  required LabTest lab,
  required LabRange? range,
  required Future<void> Function(LabResultModel) onAdd,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _AddLabResultDialog(lab: lab, range: range, onAdd: onAdd),
  );
}

class _AddLabResultDialog extends StatefulWidget {
  final LabTest lab;
  final LabRange? range;
  final Future<void> Function(LabResultModel) onAdd;
  const _AddLabResultDialog(
      {required this.lab, required this.range, required this.onAdd});
  @override
  State<_AddLabResultDialog> createState() => _AddLabResultDialogState();
}

class _AddLabResultDialogState extends State<_AddLabResultDialog> {
  final _valCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _abnormal = false; // للنوعي
  bool _saving = false;

  @override
  void dispose() {
    _valCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double? get _value =>
      double.tryParse(_valCtrl.text.trim().replaceAll(',', '.'));

  bool get _canSave => widget.lab.isQualitative || _value != null;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    final lab = widget.lab;
    String author = '';
    try {
      author = AuthController.to.user.name;
    } catch (_) {}
    final r = LabResultModel(
      labCode: lab.code,
      labName: lab.name,
      unit: lab.unit,
      value: lab.isQualitative ? null : _value,
      abnormal: lab.isQualitative ? _abnormal : null,
      takenAt: _date,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      addedByUserName: author,
    );
    try {
      await widget.onAdd(r);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      Get.snackbar('تعذّر الحفظ', '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lab = widget.lab;
    final v = _value;
    final st = (!lab.isQualitative && v != null)
        ? evaluateLabValue(lab, widget.range, v)
        : null;

    return AlertDialog(
      title: Text(lab.name,
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lab.isQualitative) ...[
              const Text('النتيجة',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('طبيعي / سلبي',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    selected: !_abnormal,
                    onSelected: (_) => setState(() => _abnormal = false),
                  ),
                  ChoiceChip(
                    label: const Text('غير طبيعي / إيجابي',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                    selected: _abnormal,
                    onSelected: (_) => setState(() => _abnormal = true),
                  ),
                ],
              ),
            ] else ...[
              TextField(
                controller: _valCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'القيمة',
                  suffixText: lab.unit,
                ),
              ),
              if (widget.range != null && widget.range!.isNumeric)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('المدى الطبيعي: ${widget.range!.text(lab.unit)}',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: AppColors.textSecond)),
                ),
              if (st != null && st != LabStatus.unknown)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(_statusText(st),
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _statusColor(st))),
                ),
            ],
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDate,
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text('تاريخ التحليل: ${_fmtDate(_date)}',
                      style:
                          const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('إلغاء')),
        ElevatedButton(
            onPressed: _canSave && !_saving ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('حفظ')),
      ],
    );
  }
}
