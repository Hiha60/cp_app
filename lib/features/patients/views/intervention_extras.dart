import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/models/intervention_model.dart';

/// عرض المرجع + بيانات الخطأ الدوائي + المتابعة (مشترك بين شاشة المريض وشاشة الطبيب)
class InterventionExtras extends StatelessWidget {
  final InterventionModel iv;
  const InterventionExtras({super.key, required this.iv});

  static const _t = TextStyle(
      fontFamily: 'Cairo', fontSize: 12, color: AppColors.textSecond);

  Widget _line(String k, String? v) => (v == null || v.isEmpty)
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('$k: $v', style: _t),
        );

  @override
  Widget build(BuildContext context) {
    final hasRef = iv.reference != null && iv.reference!.isNotEmpty;
    final hasFu = iv.followUp != null && iv.followUp!.isNotEmpty;
    if (!hasRef && !iv.isMedError && !hasFu) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasRef) _line('📚 المرجع', iv.reference),
        if (iv.isMedError)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('⚠️ خطأ دوائي',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: AppColors.danger)),
                _line('المرحلة/النوع', iv.errorStage),
                _line('الوصف', iv.errorDescription),
                _line('إجراء الصيدلاني', iv.errorAction),
                _line('السبب المحتمل', iv.errorCause),
                _line('الخطورة', iv.errorSeverity),
              ],
            ),
          ),
        if (hasFu)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('🔎 المتابعة: ${iv.followUp}',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          ),
      ],
    );
  }
}
