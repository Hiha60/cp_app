import '../../core/utils/identity.dart';

class UserModel {
  /// = Firebase Auth uid
  final String id, name, code, role, hospitalId;
  final List<String> departmentIds;
  final bool active;

  const UserModel({
    required this.id,
    required this.name,
    required this.code,
    required this.role,
    required this.hospitalId,
    required this.departmentIds,
    this.active = true,
  });

  /// مفتاح الاسم+الكود (بيتحول لإيميل Firebase Auth عن طريق emailFor)
  static String buildId(String name, String code) => userKey(name, code);

  factory UserModel.fromMap(String id, Map<String, dynamic> m) => UserModel(
        id: id,
        name: m['name'] as String? ?? '',
        code: m['code'] as String? ?? '',
        role: m['role'] as String? ?? 'pharmacist',
        hospitalId: m['hospital_id'] as String? ?? '',
        departmentIds: _parseList(m['department_ids']),
        active: m['active'] as bool? ?? false,
      );

  // يتعامل مع String أو List أو null
  static List<String> _parseList(dynamic value) {
    if (value == null) return [];
    if (value is List) return List<String>.from(value);
    if (value is String) return value.isEmpty ? [] : [value];
    return [];
  }

  UserModel copyWith({List<String>? departmentIds, bool? active}) => UserModel(
        id: id,
        name: name,
        code: code,
        role: role,
        hospitalId: hospitalId,
        departmentIds: departmentIds ?? this.departmentIds,
        active: active ?? this.active,
      );

  /// القسم الحالى (الصيدلانى والطبيب ليهم قسم واحد)
  String? get departmentId => departmentIds.isEmpty ? null : departmentIds.first;

  bool get isAdmin => role == 'admin';
  bool get isSuperAdmin => role == 'super_admin';
  bool get isPharmacist => role == 'pharmacist';
  bool get isDoctor => role == 'doctor';

  /// مدير المستشفى له صلاحيات الصيدلانى الإكلينيكى + صلاحيات الطبيب
  bool get canActAsPharmacist => isPharmacist || isAdmin;
  bool get canActAsDoctor => isDoctor || isAdmin;

  /// الأدوار اللى لازم يكون ليها قسم
  bool get needsDepartment => isPharmacist || isDoctor;
}
