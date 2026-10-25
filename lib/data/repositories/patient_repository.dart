import 'package:flutter/foundation.dart';
import '../models/patient_model.dart';
import 'firebase_rest_service.dart';

class PatientRepository {
  PatientRepository._();
  static final instance = PatientRepository._();

  final _rest = FirebaseRestService.instance;

  // ── Add ───────────────────────────────────────────────────────────────
  Future<String> addPatient(PatientModel p) async {
    return _rest.addDoc('patients', p.toRestMap());
  }

  // ── Update ────────────────────────────────────────────────────────────
  Future<void> updatePatient(String id, Map<String, dynamic> fields) async {
    await _rest.updateDoc('patients/$id', fields);
  }

  // ── نتائج التحاليل (بتستبدل القائمة كلها) ─────────────────────────────
  Future<void> updateLabResults(String id, List<LabResultModel> results) =>
      updatePatient(id, {'lab_results': results.map((e) => e.toMap()).toList()});

  // ── Fetch single patient — مرة واحدة (بدون polling) ───────────────────
  Future<PatientModel?> fetchPatient(String id) async {
    final doc = await _rest.getDoc('patients/$id');
    if (doc == null) return null;
    return PatientModel.fromRestMap(id, FirebaseRestService.docData(doc));
  }

  // ── Fetch list — مرة واحدة (بدون polling) ─────────────────────────────
  // بدون orderBy في Firestore (composite index)، والترتيب محلياً:
  // الأحدث دخولاً أولاً.
  Future<List<PatientModel>> fetchPatients({required String hospitalId}) async {
    final docs = await _rest.listDocs(
      'patients',
      where: {'hospital_id': hospitalId},
    );
    return docs
        .map((d) => PatientModel.fromRestMap(
              FirebaseRestService.docId(d),
              FirebaseRestService.docData(d),
            ))
        .toList()
      ..sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
  }

  // ── للطبيب: مرضى قسمه فقط (القواعد بتفرض ده) ─────────────────────────
  Future<List<PatientModel>> fetchByDepartment({
    required String hospitalId,
    required String departmentId,
  }) async {
    final docs = await _rest.listDocs(
      'patients',
      where: {'hospital_id': hospitalId, 'department_id': departmentId},
    );
    return docs
        .map((d) => PatientModel.fromRestMap(
              FirebaseRestService.docId(d),
              FirebaseRestService.docData(d),
            ))
        .toList()
      ..sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
  }

  // ── Stream (polling كل 4 ثواني — أول جلب فوري) ───────────────────────
  Stream<PatientModel?> streamPatient(String id) async* {
    while (true) {
      try {
        final doc = await _rest.getDoc('patients/$id');
        yield doc == null
            ? null
            : PatientModel.fromRestMap(id, FirebaseRestService.docData(doc));
      } catch (e) {
        debugPrint('streamPatient error: $e'); // لا توقف الـ stream
      }
      await Future.delayed(const Duration(seconds: 4));
    }
  }

  // ── Stream list (polling كل 5 ثواني — أول جلب فوري) ──────────────────
  // بدون orderBy في Firestore (كان بيحتاج composite index)،
  // والترتيب محلياً: الأحدث دخولاً أولاً.
  Stream<List<PatientModel>> streamPatients(
      {required String hospitalId}) async* {
    while (true) {
      try {
        final docs = await _rest.listDocs(
          'patients',
          where: {'hospital_id': hospitalId},
        );
        final list = docs
            .map((d) => PatientModel.fromRestMap(
                  FirebaseRestService.docId(d),
                  FirebaseRestService.docData(d),
                ))
            .toList()
          ..sort((a, b) => b.admissionDate.compareTo(a.admissionDate));
        yield list;
      } catch (e) {
        debugPrint('streamPatients error: $e'); // لا توقف الـ stream
      }
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  // ── Duplicate check ───────────────────────────────────────────────────
  Future<PatientModel?> findDuplicate({
    required String hospitalId,
    required String departmentId,
    required String fileNumber,
    required DateTime admissionDate,
  }) async {
    final docs = await _rest.listDocs(
      'patients',
      where: {'hospital_id': hospitalId, 'file_number': fileNumber},
      limit: 1,
    );
    if (docs.isEmpty) return null;
    final d = docs.first;
    return PatientModel.fromRestMap(
      FirebaseRestService.docId(d),
      FirebaseRestService.docData(d),
    );
  }

  // ── Discharge ─────────────────────────────────────────────────────────
  Future<void> discharge(String id) =>
      updatePatient(id, {'status': 'discharged'});

  // ── Local patterns ────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fetchLocalPatterns(
      String hospitalId) async {
    final docs = await _rest.listDocs(
      'drug_patterns',
      where: {'hospital_id': hospitalId},
    );
    return docs.map((d) => FirebaseRestService.docData(d)).toList();
  }
}
