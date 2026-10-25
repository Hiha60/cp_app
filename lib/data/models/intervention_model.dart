import 'package:flutter/material.dart';

class InterventionModel {
  final String? id;
  final String patientId, hospitalId, addedByUserId, addedByUserName;
  /// قسم المريض وقت التدخل — الطبيب بيشوف تدخلات قسمه بس (القواعد بتفرض ده)
  final String departmentId;
  final String typeCode, categoryAr, typeNameEn, typeNameAr;
  final String? drugName, altDrugName, oldValue, newValue,
      conditionName, reason, extraNote, doctorNote;
  final String comment, doctorResponse;
  final String? doctorId, doctorName;
  final DateTime? respondedAt;
  final DateTime createdAt, updatedAt;
  /// المرجع العلمي (عند الإنشاء)
  final String? reference;
  /// الخطأ الدوائي
  final bool isMedError;
  final String? errorStage, errorDescription, errorAction, errorCause,
      errorSeverity;
  /// المتابعة — بيكتبها الصيدلاني صاحب التدخل بعد التدخل
  final String? followUp;
  final DateTime? followUpAt;

  const InterventionModel({
    this.id,
    required this.patientId, required this.hospitalId,
    this.departmentId = '',
    required this.addedByUserId, required this.addedByUserName,
    required this.typeCode, required this.categoryAr,
    required this.typeNameEn, required this.typeNameAr,
    this.drugName, this.altDrugName, this.oldValue, this.newValue,
    this.conditionName, this.reason,
    required this.comment, this.extraNote,
    this.doctorResponse = 'pending', this.doctorNote,
    this.doctorId, this.doctorName, this.respondedAt,
    required this.createdAt, required this.updatedAt,
    this.reference, this.isMedError = false,
    this.errorStage, this.errorDescription, this.errorAction,
    this.errorCause, this.errorSeverity,
    this.followUp, this.followUpAt,
  });

  // ── From REST Map ─────────────────────────────────────────────────────
  factory InterventionModel.fromRestMap(String id, Map<String, dynamic> m) {
    DateTime parseDate(dynamic v) {
      if (v is DateTime) return v;
      if (v is String)   return DateTime.parse(v);
      return DateTime.now();
    }
    return InterventionModel(
      id:               id,
      patientId:        m['patient_id']         as String? ?? '',
      hospitalId:       m['hospital_id']        as String? ?? '',
      departmentId:     m['department_id']      as String? ?? '',
      addedByUserId:    m['added_by_user_id']   as String? ?? '',
      addedByUserName:  m['added_by_user_name'] as String? ?? '',
      typeCode:         m['type_code']          as String? ?? '',
      categoryAr:       m['category_ar']        as String? ?? '',
      typeNameEn:       m['type_name_en']       as String? ?? '',
      typeNameAr:       m['type_name_ar']       as String? ?? '',
      drugName:         m['drug_name']          as String?,
      altDrugName:      m['alt_drug_name']      as String?,
      oldValue:         m['old_value']          as String?,
      newValue:         m['new_value']          as String?,
      conditionName:    m['condition_name']     as String?,
      reason:           m['reason']             as String?,
      comment:          m['comment']            as String? ?? '',
      extraNote:        m['extra_note']         as String?,
      doctorResponse:   m['doctor_response']    as String? ?? 'pending',
      doctorNote:       m['doctor_note']        as String?,
      doctorId:         m['doctor_id']          as String?,
      doctorName:       m['doctor_name']        as String?,
      respondedAt:      m['responded_at'] == null ? null : parseDate(m['responded_at']),
      createdAt:        parseDate(m['created_at']),
      updatedAt:        parseDate(m['updated_at']),
      reference:        m['reference']          as String?,
      isMedError:       m['is_med_error']       as bool? ?? false,
      errorStage:       m['error_stage']        as String?,
      errorDescription: m['error_description']  as String?,
      errorAction:      m['error_action']       as String?,
      errorCause:       m['error_cause']        as String?,
      errorSeverity:    m['error_severity']     as String?,
      followUp:         m['follow_up']          as String?,
      followUpAt:       m['follow_up_at'] == null ? null : parseDate(m['follow_up_at']),
    );
  }

  // ── To REST Map (للإنشاء فقط — حقول الطبيب بتتكتب من رد الطبيب بس) ──────
  Map<String, dynamic> toRestMap() => {
    'patient_id':         patientId,
    'hospital_id':        hospitalId,
    'department_id':      departmentId,
    'added_by_user_id':   addedByUserId,
    'added_by_user_name': addedByUserName,
    'type_code':          typeCode,
    'category_ar':        categoryAr,
    'type_name_en':       typeNameEn,
    'type_name_ar':       typeNameAr,
    'drug_name':          drugName,
    'alt_drug_name':      altDrugName,
    'old_value':          oldValue,
    'new_value':          newValue,
    'condition_name':     conditionName,
    'reason':             reason,
    'comment':            comment,
    'extra_note':         extraNote,
    'doctor_response':    'pending',
    'doctor_note':        null,
    'reference':          reference,
    'is_med_error':       isMedError,
    'error_stage':        isMedError ? errorStage : null,
    'error_description':  isMedError ? errorDescription : null,
    'error_action':       isMedError ? errorAction : null,
    'error_cause':        isMedError ? errorCause : null,
    'error_severity':     isMedError ? errorSeverity : null,
    'follow_up':          null,
    'follow_up_at':       null,
    'created_at':         createdAt.toUtc().toIso8601String(),
    'updated_at':         updatedAt.toUtc().toIso8601String(),
  };

  static String buildComment({
    required String template, String? drug, String? alt,
    String? old, String? newVal, String? condition, String? reason,
  }) => template
      .replaceAll('[DRUG]',      drug      ?? '—')
      .replaceAll('[ALT]',       alt       ?? '—')
      .replaceAll('[OLD]',       old       ?? '—')
      .replaceAll('[NEW]',       newVal    ?? '—')
      .replaceAll('[CONDITION]', condition ?? '—')
      .replaceAll('[REASON]',    reason    ?? '—');

  bool get isPending => doctorResponse == 'pending';

  String get responseLabel => switch (doctorResponse) {
    'accepted' => '✅ قبل الطبيب',
    'rejected' => '❌ رفض الطبيب',
    'partial'  => '🔶 قبول جزئي',
    'considered' => '🟣 تم الأخذ في الاعتبار',
    _          => '⏳ في الانتظار',
  };

  Color get responseColor => switch (doctorResponse) {
    'accepted' => const Color(0xFF22C55E),
    'rejected' => const Color(0xFFEF4444),
    'partial'  => const Color(0xFFF59E0B),
    'considered' => const Color(0xFF8B5CF6),
    _          => const Color(0xFF6B7280),
  };

  InterventionModel copyWith({
    String? comment, String? extraNote,
    String? doctorResponse, String? doctorNote,
    String? doctorId, String? doctorName, DateTime? respondedAt,
    String? followUp, DateTime? followUpAt,
  }) => InterventionModel(
    id: id, patientId: patientId, hospitalId: hospitalId,
    departmentId: departmentId,
    addedByUserId: addedByUserId, addedByUserName: addedByUserName,
    typeCode: typeCode, categoryAr: categoryAr,
    typeNameEn: typeNameEn, typeNameAr: typeNameAr,
    drugName: drugName, altDrugName: altDrugName,
    oldValue: oldValue, newValue: newValue,
    conditionName: conditionName, reason: reason,
    comment:        comment        ?? this.comment,
    extraNote:      extraNote      ?? this.extraNote,
    doctorResponse: doctorResponse ?? this.doctorResponse,
    doctorNote:     doctorNote     ?? this.doctorNote,
    doctorId:       doctorId       ?? this.doctorId,
    doctorName:     doctorName     ?? this.doctorName,
    respondedAt:    respondedAt    ?? this.respondedAt,
    createdAt: createdAt, updatedAt: DateTime.now(),
    reference: reference, isMedError: isMedError,
    errorStage: errorStage, errorDescription: errorDescription,
    errorAction: errorAction, errorCause: errorCause,
    errorSeverity: errorSeverity,
    followUp:   followUp   ?? this.followUp,
    followUpAt: followUpAt ?? this.followUpAt,
  );
}
