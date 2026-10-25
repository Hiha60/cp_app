import '../../core/constants/app_constants.dart';
import '../models/org_models.dart';
import '../models/user_model.dart';
import 'auth_repository.dart';
import 'firebase_rest_service.dart';

/// المستشفيات + الأقسام + طلبات تغيير القسم.
/// كل الصلاحيات بتتفرض فى firestore.rules — الكود هنا مجرد واجهة.
class OrgRepository {
  OrgRepository._();
  static final instance = OrgRepository._();

  final _rest = FirebaseRestService.instance;

  // ── مستشفى جديدة + مدير ليها (Super Admin) ────────────────────────────
  Future<String> createHospitalWithAdmin({
    required String hospitalName,
    required String adminName,
    required String adminCode,
    required String adminPassword,
  }) async {
    final adminUid = await AuthRepository.instance.registerAccount(
      name: adminName,
      code: adminCode,
      password: adminPassword,
    );
    final hospitalId = _rest.newId();
    try {
      // ذرّى: المستشفى + المدير يتكتبوا مع بعض أو ولا واحد
      await _rest.commit([
        WriteOp.set(
          'hospitals/$hospitalId',
          {'name': hospitalName.trim()},
          serverTimeFields: const ['created_at'],
          createOnly: true,
        ),
        WriteOp.set(
          'users/$adminUid',
          {
            'name': adminName.trim(),
            'code': adminCode.trim(),
            'role': UserRole.admin,
            'hospital_id': hospitalId,
            'department_ids': <String>[],
            'active': true,
            'created_by': _rest.uid,
          },
          serverTimeFields: const ['created_at'],
          createOnly: true,
        ),
      ]);
    } on ApiException catch (e) {
      if (e.isPermissionDenied || e.status == 409) {
        throw const AuthException(
            'تعذّر إنشاء المستشفى: المدير موجود بالفعل أو لا تملك الصلاحية');
      }
      rethrow;
    }
    return hospitalId;
  }

  Future<List<HospitalModel>> listHospitals() async {
    final docs = await _rest.listDocs('hospitals');
    final list = docs
        .map((d) => HospitalModel(
              FirebaseRestService.docId(d),
              FirebaseRestService.docData(d)['name'] as String? ?? '',
            ))
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  // ── الأقسام ───────────────────────────────────────────────────────────
  Future<List<DepartmentModel>> departments(String hospitalId) async {
    if (hospitalId.isEmpty) return [];
    final docs =
        await _rest.listDocs('departments', where: {'hospital_id': hospitalId});
    final list = docs.map((d) {
      final m = FirebaseRestService.docData(d);
      return DepartmentModel(
        FirebaseRestService.docId(d),
        m['name'] as String? ?? '',
        m['hospital_id'] as String? ?? '',
      );
    }).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<void> addDepartment(String hospitalId, String name) =>
      _rest.addDoc('departments', {
        'hospital_id': hospitalId,
        'name': name.trim(),
      });

  // ── طلب تغيير القسم (صيدلانى) ─────────────────────────────────────────
  Future<DeptRequest?> myRequest(String uid) async {
    final doc = await _rest.getDoc('dept_requests/$uid');
    return doc == null ? null : DeptRequest.fromDoc(doc);
  }

  Future<void> requestChange({
    required UserModel user,
    required String toDeptId,
  }) async {
    final existing = await myRequest(user.id);
    if (existing != null && existing.isPending) {
      throw const AuthException('عندك طلب تغيير قسم قيد المراجعة بالفعل');
    }
    // مستند واحد لكل صيدلانى (id = uid) — القواعد بتمنع طلبين pending
    await _rest.commit([
      WriteOp.set(
        'dept_requests/${user.id}',
        {
          'user_id': user.id,
          'user_name': user.name,
          'hospital_id': user.hospitalId,
          'from_dept_id': user.departmentId ?? '',
          'to_dept_id': toDeptId,
          'status': 'pending',
        },
        serverTimeFields: const ['created_at'],
      ),
    ]);
  }

  /// طلبات القسم المعلّقة فى مستشفى المدير (بعد تطبيق اللى عدّى وقته)
  Future<List<DeptRequest>> pendingForHospital(String hospitalId) async {
    if (hospitalId.isEmpty) return [];
    final docs = await _rest.listDocs('dept_requests',
        where: {'hospital_id': hospitalId, 'status': 'pending'});
    final all = docs.map(DeptRequest.fromDoc).toList();
    for (final r in all.where((r) => r.isExpired)) {
      await _applyExpired(r);
    }
    final list = all.where((r) => !r.isExpired).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  // ── موافقة المدير ─────────────────────────────────────────────────────
  Future<void> approve(DeptRequest r) => _rest.commit([
        WriteOp.update('users/${r.userId}', {
          'department_ids': [r.toDeptId],
        }),
        WriteOp.update(
          'dept_requests/${r.id}',
          {'status': 'approved', 'resolved_by': _rest.uid},
          serverTimeFields: const ['resolved_at'],
        ),
      ]);

  // ── رفض المدير + اختيار القسم اللى هو عايزه ───────────────────────────
  Future<void> rejectAndAssign(DeptRequest r, String chosenDeptId) =>
      _rest.commit([
        WriteOp.update('users/${r.userId}', {
          'department_ids': [chosenDeptId],
        }),
        WriteOp.update(
          'dept_requests/${r.id}',
          {
            'status': 'rejected',
            'chosen_dept_id': chosenDeptId,
            'resolved_by': _rest.uid,
          },
          serverTimeFields: const ['resolved_at'],
        ),
      ]);

  // ── انتهاء المهلة بدون رد → التغيير يتطبق ─────────────────────────────
  /// بيتنادى من جهاز الصيدلانى (عند الدخول) أو من جهاز المدير (فى تاب الطلبات).
  /// السيرفر هو اللى بيحسم المهلة، فلو ساعة الجهاز متقدمة العملية بتترفض وبنتجاهلها.
  Future<bool> _applyExpired(DeptRequest r) async {
    if (!r.isPending || !r.isExpired) return false;
    try {
      await _rest.commit([
        WriteOp.update('users/${r.userId}', {
          'department_ids': [r.toDeptId],
        }),
        WriteOp.update(
          'dept_requests/${r.id}',
          {'status': 'auto_approved', 'resolved_by': _rest.uid},
          serverTimeFields: const ['resolved_at'],
        ),
      ]);
      return true;
    } on ApiException {
      return false;
    }
  }

  /// للصيدلانى: لو طلبه معدّى مهلته يتطبق. بيرجّع true لو القسم اتغيّر.
  Future<bool> applyMyExpired(String uid) async {
    final r = await myRequest(uid);
    if (r == null) return false;
    return _applyExpired(r);
  }
}
