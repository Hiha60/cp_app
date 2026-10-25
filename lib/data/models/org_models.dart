import '../repositories/firebase_rest_service.dart';

/// مهلة الموافقة التلقائية على طلب تغيير القسم.
/// ⚠️ لازم تفضل مطابقة لـ duration.value(24, 'h') فى firestore.rules
const kDeptAutoApproveHours = 24;

class HospitalModel {
  final String id, name;
  const HospitalModel(this.id, this.name);
}

class DepartmentModel {
  final String id, name, hospitalId;
  const DepartmentModel(this.id, this.name, this.hospitalId);
}

class DeptRequest {
  /// = uid الصيدلانى (مستند واحد لكل مستخدم)
  final String id, userId, userName, hospitalId, fromDeptId, toDeptId, status;
  final String? chosenDeptId;
  final DateTime createdAt;

  const DeptRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.hospitalId,
    required this.fromDeptId,
    required this.toDeptId,
    required this.status,
    required this.createdAt,
    this.chosenDeptId,
  });

  factory DeptRequest.fromDoc(Map<String, dynamic> d) {
    final m = FirebaseRestService.docData(d);
    return DeptRequest(
      id: FirebaseRestService.docId(d),
      userId: m['user_id'] as String? ?? '',
      userName: m['user_name'] as String? ?? '',
      hospitalId: m['hospital_id'] as String? ?? '',
      fromDeptId: m['from_dept_id'] as String? ?? '',
      toDeptId: m['to_dept_id'] as String? ?? '',
      status: m['status'] as String? ?? 'pending',
      chosenDeptId: m['chosen_dept_id'] as String?,
      createdAt: (m['created_at'] as DateTime?) ?? DateTime.now(),
    );
  }

  bool get isPending => status == 'pending';

  DateTime get autoApproveAt =>
      createdAt.add(const Duration(hours: kDeptAutoApproveHours));

  /// المهلة عدّت (بساعة الجهاز — السيرفر هو اللى بيحسم فى الآخر)
  bool get isExpired => DateTime.now().isAfter(autoApproveAt);
}
