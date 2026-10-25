import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/org_models.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/firebase_rest_service.dart';
import '../../../data/repositories/org_repository.dart';
import '../../auth/controllers/auth_controller.dart';
import 'departments_tab.dart';
import 'hospitals_tab.dart';
import 'requests_tab.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  CONTROLLER
// ─────────────────────────────────────────────────────────────────────────────
class AdminController extends GetxController {
  final users        = <UserModel>[].obs;
  final departments  = <DepartmentModel>[].obs;
  final isLoading    = false.obs;
  final pendingCount = 0.obs;

  String get hospitalId => AuthController.to.user.hospitalId;

  @override
  void onInit() {
    super.onInit();
    loadUsers();
    loadDepartments();
    refreshPending();
  }

  Future<void> loadUsers() async {
    if (hospitalId.isEmpty) return;
    isLoading.value = true;
    try {
      final all = await AuthRepository.instance.fetchUsersByHospital(hospitalId);
      users.value = all.where((u) => u.active).toList();
    } on ApiException catch (e) {
      Get.snackbar('خطأ', e.message);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadDepartments() async {
    try {
      departments.value = await OrgRepository.instance.departments(hospitalId);
    } on ApiException catch (_) {}
  }

  Future<void> refreshPending() async {
    try {
      final r = await OrgRepository.instance.pendingForHospital(hospitalId);
      pendingCount.value = r.length;
    } on ApiException catch (_) {}
  }

  /// بيقرا الـ Rx دايمًا (حتى لو id فاضى) عشان أى Obx بيناديها يلاقى حاجة يراقبها.
  String deptName(String? id) {
    final list = departments.toList();
    if (id == null || id.isEmpty) return '—';
    return list.where((d) => d.id == id).firstOrNull?.name ?? '—';
  }

  Future<void> deactivateUser(String id) async {
    try {
      await AuthRepository.instance.deactivateUser(id);
      users.removeWhere((u) => u.id == id);
    } on ApiException catch (e) {
      Get.snackbar('خطأ', e.message);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(AdminController());
    final me = AuthController.to.user;
    final hasHospital = me.hospitalId.isNotEmpty;

    final tabs = <({String label, IconData icon, Widget page, bool badge})>[
      if (hasHospital) (
        label: 'المستخدمون',
        icon: Icons.people_outline_rounded,
        page: _UsersTab(ctrl: ctrl),
        badge: false,
      ),
      if (hasHospital) (
        label: 'إضافة مستخدم',
        icon: Icons.person_add_outlined,
        page: _AddUserTab(ctrl: ctrl),
        badge: false,
      ),
      if (hasHospital) (
        label: 'الأقسام',
        icon: Icons.apartment_rounded,
        page: DepartmentsTab(ctrl: ctrl),
        badge: false,
      ),
      if (hasHospital) (
        label: 'طلبات القسم',
        icon: Icons.swap_horiz_rounded,
        page: RequestsTab(ctrl: ctrl),
        badge: true,
      ),
      if (me.isSuperAdmin) (
        label: 'المستشفيات',
        icon: Icons.local_hospital_outlined,
        page: const HospitalsTab(),
        badge: false,
      ),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              labelStyle: const TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 13),
              tabs: [
                for (final t in tabs)
                  Tab(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(t.icon, size: 18),
                      const SizedBox(width: 6),
                      Text(t.label),
                      if (t.badge)
                        Obx(() => ctrl.pendingCount.value == 0
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Badge(
                                    label: Text('${ctrl.pendingCount.value}')),
                              )),
                    ]),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(children: [for (final t in tabs) t.page]),
          ),
        ],
      ),
    );
  }
}

// ── Users Tab ─────────────────────────────────────────────────────────────────
class _UsersTab extends StatelessWidget {
  final AdminController ctrl;
  const _UsersTab({required this.ctrl});

  @override
  Widget build(BuildContext context) => Obx(() {
    if (ctrl.isLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline_rounded, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text('لا يوجد مستخدمون بعد',
                style: TextStyle(fontFamily:'Cairo', color:AppColors.textSecond)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await ctrl.loadUsers();
        await ctrl.loadDepartments();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: ctrl.users.length,
        itemBuilder: (_, i) => _UserCard(user: ctrl.users[i], ctrl: ctrl),
      ),
    );
  });
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final AdminController ctrl;
  const _UserCard({required this.user, required this.ctrl});

  /// نفس القاعدة اللى فى firestore.rules:
  ///  - السوبر أدمن يعطّل أى مستخدم غير نفسه
  ///  - المدير يعطّل الصيادلة والأطباء بس
  bool _canDeactivate(UserModel me) {
    if (user.id == me.id) return false;
    if (me.isSuperAdmin) return true;
    if (me.isAdmin) return user.isPharmacist || user.isDoctor;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final auth    = AuthController.to;
    final isMe    = user.id == auth.user.id;
    final roleColor = switch (user.role) {
      UserRole.superAdmin => AppColors.danger,
      UserRole.admin      => AppColors.warning,
      UserRole.doctor     => AppColors.success,
      _                   => AppColors.primary,
    };
    final roleLabel = switch (user.role) {
      UserRole.superAdmin => 'Super Admin',
      UserRole.admin      => 'مدير',
      UserRole.doctor     => 'طبيب',
      _                   => 'صيدلاني',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: roleColor.withOpacity(0.12),
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: TextStyle(fontFamily:'Cairo', color:roleColor, fontWeight:FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(user.name,
                          style: const TextStyle(fontFamily:'Cairo', fontWeight:FontWeight.w700, fontSize:14)),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal:6, vertical:1),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text('أنت', style: TextStyle(fontFamily:'Cairo', fontSize:10, color:AppColors.success)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Obx(() {
                    final dept = ctrl.deptName(user.departmentId);
                    return Text(
                        user.needsDepartment
                            ? 'كود: ${user.code}  •  $dept'
                            : 'كود: ${user.code}',
                        style: const TextStyle(fontFamily:'Cairo', fontSize:12, color:AppColors.textSecond));
                  }),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal:8, vertical:3),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color:roleColor.withOpacity(0.3)),
                  ),
                  child: Text(roleLabel,
                      style: TextStyle(fontFamily:'Cairo', fontSize:11, color:roleColor, fontWeight:FontWeight.w600)),
                ),
                if (_canDeactivate(auth.user)) ...[
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _confirmDeactivate(context, user, ctrl),
                    child: const Text('تعطيل',
                        style: TextStyle(fontFamily:'Cairo', fontSize:11, color:AppColors.danger)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeactivate(BuildContext ctx, UserModel u, AdminController ctrl) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('تعطيل المستخدم', style:TextStyle(fontFamily:'Cairo', fontWeight:FontWeight.w700)),
        content: Text(
            'هل تريد تعطيل "${u.name}"؟ مش هيقدر يدخل تانى، '
            'وبياناته القديمة (مرضى/تدخلات) هتفضل محفوظة.',
            style: const TextStyle(fontFamily:'Cairo')),
        actions: [
          TextButton(onPressed: ()=>Get.back(), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor:AppColors.danger),
            onPressed: () { Get.back(); ctrl.deactivateUser(u.id); },
            child: const Text('تعطيل'),
          ),
        ],
      ),
    );
  }
}

// ── Add User Tab ──────────────────────────────────────────────────────────────
class _AddUserTab extends StatefulWidget {
  final AdminController ctrl;
  const _AddUserTab({required this.ctrl});
  @override State<_AddUserTab> createState() => _AddUserTabState();
}

class _AddUserTabState extends State<_AddUserTab> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _codeCtrl  = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  String  _role    = UserRole.pharmacist;
  String? _deptId;
  bool    _showPass = false;
  bool    _saving   = false;

  bool get _needsDept => _role == UserRole.pharmacist || _role == UserRole.doctor;

  @override
  void dispose() {
    for (final c in [_nameCtrl,_codeCtrl,_passCtrl,_pass2Ctrl]) c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final auth = AuthController.to;
      final uid = await AuthRepository.instance.createUser(
        name:          _nameCtrl.text.trim(),
        code:          _codeCtrl.text.trim(),
        password:      _passCtrl.text,
        role:          _role,
        hospitalId:    auth.user.hospitalId,
        departmentIds: _needsDept ? [_deptId!] : const [],
      );
      widget.ctrl.users.add(UserModel(
        id: uid,
        name: _nameCtrl.text.trim(),
        code: _codeCtrl.text.trim(),
        role: _role,
        hospitalId: auth.user.hospitalId,
        departmentIds: _needsDept ? [_deptId!] : const [],
      ));

      Get.snackbar('✅ تم', 'تم إضافة المستخدم بنجاح',
          backgroundColor:AppColors.success, colorText:Colors.white,
          snackPosition: SnackPosition.BOTTOM);

      _nameCtrl.clear(); _codeCtrl.clear();
      _passCtrl.clear(); _pass2Ctrl.clear();
      setState(() { _role = UserRole.pharmacist; _deptId = null; });
    } on AuthException catch (e) {
      Get.snackbar('خطأ', e.message,
          backgroundColor:AppColors.danger, colorText:Colors.white,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('خطأ', e.message,
          backgroundColor:AppColors.danger, colorText:Colors.white,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('خطأ', 'فشل الإضافة: $e',
          backgroundColor:AppColors.danger, colorText:Colors.white,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('بيانات المستخدم الجديد',
              style: TextStyle(fontFamily:'Cairo', fontSize:16, fontWeight:FontWeight.w700)),
          const SizedBox(height: 20),

          // الاسم
          _Label('اسم المستخدم'),
          TextFormField(
            controller: _nameCtrl,
            textDirection: TextDirection.rtl,
            validator: (v) => (v==null||v.trim().isEmpty) ? 'أدخل الاسم' : null,
            decoration: const InputDecoration(
              hintText: 'مثال: ahmed',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 14),

          // الكود
          _Label('الرقم التعريفي (4 أرقام)'),
          TextFormField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              if (v==null||v.trim().isEmpty) return 'أدخل الكود';
              if (!RegExp(r'^\d{4}$').hasMatch(v.trim())) return '4 أرقام فقط';
              return null;
            },
            decoration: const InputDecoration(
              hintText: '0000',
              prefixIcon: Icon(Icons.tag_rounded),
              counterText: '',
            ),
          ),
          const SizedBox(height: 14),

          // الصلاحية
          _Label('الصلاحية'),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color:Colors.grey.shade300),
            ),
            child: Column(
              children: [
                _RoleTile(
                  title: 'صيدلاني',
                  subtitle: 'إضافة مرضى + تدخلات (القسم إجبارى)',
                  value: UserRole.pharmacist,
                  groupValue: _role,
                  onChanged: (v) => setState(() => _role = v!),
                ),
                const Divider(height:1),
                _RoleTile(
                  title: 'طبيب',
                  subtitle: 'يشوف تدخلات قسمه ويوافق أو يرفض (القسم إجبارى)',
                  value: UserRole.doctor,
                  groupValue: _role,
                  onChanged: (v) => setState(() => _role = v!),
                ),
                if (AuthController.to.user.isSuperAdmin) ...[
                  const Divider(height:1),
                  _RoleTile(
                    title: 'مدير',
                    subtitle: 'إدارة المستخدمين والأقسام',
                    value: UserRole.admin,
                    groupValue: _role,
                    onChanged: (v) => setState(() => _role = v!),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // القسم (إجبارى للصيدلانى والطبيب)
          if (_needsDept) ...[
            _Label('القسم'),
            Obx(() {
              final depts = widget.ctrl.departments;
              if (depts.isEmpty) {
                return const Text(
                    'مفيش أقسام. أضف قسم الأول من تاب "الأقسام".',
                    style: TextStyle(fontFamily:'Cairo', fontSize:12, color:AppColors.warning));
              }
              return DropdownButtonFormField<String>(
                value: depts.any((d) => d.id == _deptId) ? _deptId : null,
                isExpanded: true,
                items: depts
                    .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                    .toList(),
                validator: (v) => v == null ? 'اختر القسم (إجبارى)' : null,
                onChanged: (v) => setState(() => _deptId = v),
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.apartment_rounded)),
              );
            }),
            const SizedBox(height: 14),
          ],

          // كلمة المرور
          _Label('كلمة المرور'),
          TextFormField(
            controller: _passCtrl,
            obscureText: !_showPass,
            textDirection: TextDirection.ltr,
            validator: AuthController.validateNewPassword,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _showPass = !_showPass),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // تأكيد
          _Label('تأكيد كلمة المرور'),
          TextFormField(
            controller: _pass2Ctrl,
            obscureText: !_showPass,
            textDirection: TextDirection.ltr,
            validator: (v) {
              if (v != _passCtrl.text) return 'كلمتا المرور غير متطابقتين';
              return null;
            },
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          const SizedBox(height: 24),

          // زر الإضافة
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width:18,height:18,child:CircularProgressIndicator(color:Colors.white,strokeWidth:2))
                  : const Icon(Icons.person_add_rounded),
              label: Text(_saving ? 'جاري الإضافة...' : 'إضافة المستخدم',
                  style: const TextStyle(fontFamily:'Cairo', fontWeight:FontWeight.w700, fontSize:16)),
            ),
          ),

          const SizedBox(height: 24),
          // تعليمات
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color:AppColors.info.withOpacity(0.2)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📌 ملاحظات:', style:TextStyle(fontFamily:'Cairo', fontWeight:FontWeight.w700, fontSize:13, color:AppColors.info)),
                SizedBox(height:6),
                Text('• تسجيل الدخول بالاسم + الكود + كلمة المرور', style:TextStyle(fontFamily:'Cairo', fontSize:12)),
                Text('• لازم يكون الاسم + الكود فريدَين معاً', style:TextStyle(fontFamily:'Cairo', fontSize:12)),
                Text('• كلمة المرور 8 خانات على الأقل (حروف وأرقام)', style:TextStyle(fontFamily:'Cairo', fontSize:12)),
                Text('• كلمة المرور مش بتتخزن عندنا ولا يمكن استعادتها؛ المستخدم يغيّرها من قائمته', style:TextStyle(fontFamily:'Cairo', fontSize:12)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom:6),
    child: Text(text, style: const TextStyle(fontFamily:'Cairo', fontSize:13, fontWeight:FontWeight.w600)),
  );
}

class _RoleTile extends StatelessWidget {
  final String title, subtitle, value, groupValue;
  final void Function(String?) onChanged;
  const _RoleTile({
    required this.title, required this.subtitle,
    required this.value, required this.groupValue,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => RadioListTile<String>(
    title:    Text(title,    style: const TextStyle(fontFamily:'Cairo', fontWeight:FontWeight.w600, fontSize:14)),
    subtitle: Text(subtitle, style: const TextStyle(fontFamily:'Cairo', fontSize:12, color:AppColors.textSecond)),
    value:    value,
    groupValue: groupValue,
    onChanged: onChanged,
    activeColor: AppColors.primary,
    contentPadding: const EdgeInsets.symmetric(horizontal:12, vertical:4),
  );
}
