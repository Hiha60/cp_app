import '../models/intervention_model.dart';
import '../models/user_model.dart';
import 'firebase_rest_service.dart';

class InterventionRepository {
  InterventionRepository._();
  static final instance = InterventionRepository._();

  final _rest = FirebaseRestService.instance;

  InterventionModel _fromDoc(Map<String, dynamic> d) =>
      InterventionModel.fromRestMap(
        FirebaseRestService.docId(d),
        FirebaseRestService.docData(d),
      );

  // ── Add ───────────────────────────────────────────────────────────────
  Future<String> addIntervention(InterventionModel iv) async {
    return _rest.addDoc('interventions', iv.toRestMap());
  }

  // ── تدخلات مريض — مرة واحدة (بدون polling) ────────────────────────────
  /// hospitalId لازم يتبعت: قواعد Firestore بتشترط إن الاستعلام يتقيّد بالمستشفى.
  Future<List<InterventionModel>> fetchByPatient(
    String patientId, {
    required String hospitalId,
  }) async {
    final docs = await _rest.listDocs(
      'interventions',
      where: {'patient_id': patientId, 'hospital_id': hospitalId},
    ); // بدون orderBy (composite index)
    return docs.map(_fromDoc).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // توافق مع الكود القديم: Stream بقيمة واحدة بس (مفيش polling)
  Stream<List<InterventionModel>> streamByPatient(
    String patientId, {
    required String hospitalId,
  }) =>
      Stream.fromFuture(fetchByPatient(patientId, hospitalId: hospitalId));

  // ── Delete (القواعد: الصيدلانى صاحب التدخل وهو لسه pending فقط) ───────
  Future<void> deleteIntervention(String id) async {
    await _rest.deleteDoc('interventions/$id');
  }

  // ── للطبيب: تدخلات قسمه فقط ───────────────────────────────────────────
  Future<List<InterventionModel>> fetchForDoctor({
    required String hospitalId,
    required String departmentId,
  }) async {
    final docs = await _rest.listDocs(
      'interventions',
      where: {'hospital_id': hospitalId, 'department_id': departmentId},
    );
    return docs.map(_fromDoc).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// مدير المستشفى: كل تدخلات المستشفى
  Future<List<InterventionModel>> fetchAllForHospital(String hospitalId) async {
    final docs =
        await _rest.listDocs('interventions', where: {'hospital_id': hospitalId});
    return docs.map(_fromDoc).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // ── رد الطبيب (مرة واحدة، ومتسجل باسمه ووقت السيرفر) ──────────────────
  /// القواعد بتضمن: دكتور فى نفس قسم التدخل + التدخل لسه pending +
  /// doctor_id هو المستخدم نفسه + responded_at = وقت السيرفر.
  Future<void> respondAsDoctor({
    required String id,
    required String response, // accepted | rejected | partial | considered
    required UserModel doctor,
    String? note,
  }) async {
    assert(const ['accepted', 'rejected', 'partial', 'considered'].contains(response));
    await _rest.commit([
      WriteOp.update(
        'interventions/$id',
        {
          'doctor_response': response,
          'doctor_id': doctor.id,
          'doctor_name': doctor.name,
          if (note != null) 'doctor_note': note,
        },
        serverTimeFields: const ['responded_at'],
      ),
    ]);
  }

  /// المتابعة بعد التدخل — الصيدلانى صاحب التدخل فقط، مرة واحدة.
  /// القواعد بتفرض: follow_up_at = وقت السيرفر وإن المتابعة لسه فاضية.
  Future<void> addFollowUp({required String id, required String text}) async {
    await _rest.commit([
      WriteOp.update(
        'interventions/$id',
        {'follow_up': text.trim()},
        serverTimeFields: const ['follow_up_at'],
      ),
    ]);
  }

  // ── Fetch for reports ─────────────────────────────────────────────────
  Future<List<InterventionModel>> fetchByHospital({
    required String hospitalId,
    required DateTime from,
    required DateTime to,
  }) async {
    final docs = await _rest.listDocs(
      'interventions',
      where: {'hospital_id': hospitalId}, // بدون orderBy (composite index)
    );
    return docs
        .map(_fromDoc)
        .where((iv) =>
            iv.createdAt.isAfter(from) && iv.createdAt.isBefore(to))
        .toList();
  }
}
