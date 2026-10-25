import 'package:flutter/material.dart';
import 'package:get/get.dart';

// Package Imports (Prevents relative path errors)
import 'package:cp_app/core/constants/app_constants.dart';
import 'package:cp_app/data/models/user_model.dart';
import 'package:cp_app/data/repositories/org_repository.dart';
import 'package:cp_app/features/admin/views/admin_screen.dart';
import 'package:cp_app/features/auth/controllers/auth_controller.dart';
import 'package:cp_app/features/auth/views/change_password_dialog.dart';
import 'package:cp_app/features/doctor/views/doctor_home_screen.dart';
import 'package:cp_app/features/patients/controllers/patients_controller.dart';
import 'package:cp_app/features/patients/views/add_patient_screen.dart';
import 'package:cp_app/features/patients/views/patients_screen.dart';
import 'package:cp_app/features/reports/views/reports_screen.dart';

// Same-directory relative imports
import 'change_department_dialog.dart';
import 'dashboard_screen.dart';

// ── Nav Item ──────────────────────────────────────────────────────────────────
enum _Access { everyone, pharmacist, doctor, admin }

class _NavItem {
  final IconData icon, activeIcon;
  final String label;
  final _Access access;
  final bool showsAdminBadge;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.access = _Access.everyone,
    this.showsAdminBadge = false,
  });

  bool allowedFor(UserModel u) => switch (access) {
        _Access.everyone   => true,
        _Access.pharmacist => u.canActAsPharmacist,
        _Access.doctor     => u.isAdmin,
        _Access.admin      => u.isAdmin || u.isSuperAdmin,
      };
}

const _allNavItems = [
  _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'الرئيسية'),
  _NavItem(
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      label: 'المرضى'),
  // إضافة مريض: للصيادلة فقط (المريض بيتسجل على قسم الصيدلانى)
  _NavItem(
      icon: Icons.person_add_outlined,
      activeIcon: Icons.person_add_rounded,
      label: 'إضافة مريض',
      access: _Access.pharmacist),
  _NavItem(
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart_rounded,
      label: 'التقارير'),
  // مراجعة التدخلات (صلاحية الطبيب) — لمدير المستشفى
  _NavItem(
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check_rounded,
      label: 'مراجعة التدخلات',
      access: _Access.doctor),
  _NavItem(
      icon: Icons.admin_panel_settings_outlined,
      activeIcon: Icons.admin_panel_settings_rounded,
      label: 'الإدارة',
      access: _Access.admin,
      showsAdminBadge: true),
];

// Tab المناظر لكل nav item (بالترتيب)
const _allTabs = [
  DashboardScreen(),
  PatientsScreen(),
  AddPatientScreen(),
  ReportsScreen(),
  DoctorHomeScreen(embedded: true),
  AdminScreen(),
];

// ── Controller ────────────────────────────────────────────────────────────────
class HomeController extends GetxController {
  final currentIndex = 0.obs;

  /// اسم قسم المستخدم (للصيدلانى)
  final deptName = ''.obs;

  /// نص طلب تغيير القسم المعلّق (للصيدلانى)
  final pendingChangeText = ''.obs;

  /// عدد طلبات تغيير القسم المعلّقة (للمدير) — إشعار على تاب "الإدارة"
  final pendingRequests = 0.obs;

  @override
  void onInit() {
    super.onInit();
    final pc = Get.put(PatientsController(), permanent: true);
    // الرجوع للرئيسية (مثلاً بعد حفظ مريض) → بيانات جديدة. لو الـ controller
    // لسه بيحمّل أول مرة بيتجاهل الطلب التاني.
    pc.load(force: true);
    refreshOrg();
  }

  void go(int i) {
    currentIndex.value = i;
    // الرئيسية / المرضى → حمّل بيانات جديدة (بفاصل 15 ثانية بين كل تحميلين)
    if (i <= 1) PatientsController.to.load();
    // تحديث عدّاد طلبات القسم للمدير عند التنقل (الصيدلانى بيتحدّث عند الفتح بس)
    final me = AuthController.to.user;
    if (me.isAdmin || me.isSuperAdmin) refreshOrg();
  }

  Future<void> refreshOrg() async {
    final me = AuthController.to.user;
    try {
      if (me.isPharmacist) {
        final org = OrgRepository.instance;
        // لو طلبه عدّت مهلته يتطبق ونحدّث بياناته
        if (await org.applyMyExpired(me.id)) {
          await AuthController.to.refreshUser();
        }
        final u = AuthController.to.user;
        final depts = await org.departments(u.hospitalId);
        String nameOf(String? id) =>
            depts.where((d) => d.id == id).firstOrNull?.name ?? '';
        deptName.value = nameOf(u.departmentId);
        final r = await org.myRequest(u.id);
        pendingChangeText.value = (r != null && r.isPending)
            ? 'طلب تغيير القسم إلى ${nameOf(r.toDeptId)} قيد المراجعة'
            : '';
      } else if ((me.isAdmin || me.isSuperAdmin) && me.hospitalId.isNotEmpty) {
        final r = await OrgRepository.instance.pendingForHospital(me.hospitalId);
        pendingRequests.value = r.length;
      }
    } catch (_) {
      // مش حرجة — بتتحدث تانى عند التنقل
    }
  }

  Future<void> changeDepartment() async {
    if (await showChangeDepartmentDialog()) refreshOrg();
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.to;

    // الطبيب له شاشته الخاصة (تدخلات قسمه فقط)
    if (auth.user.isDoctor) return const DoctorHomeScreen();

    final ctrl = Get.put(HomeController());
    final me = auth.user;

    // خريطة: visible index → real tab index
    final visibleIndexes = <int>[];
    for (var i = 0; i < _allNavItems.length; i++) {
      if (_allNavItems[i].allowedFor(me)) visibleIndexes.add(i);
    }
    final visibleItems = [for (final i in visibleIndexes) _allNavItems[i]];

    final isWide = MediaQuery.of(context).size.width > 700;

    return isWide
        ? _WideLayout(ctrl: ctrl, items: visibleItems, tabIndexes: visibleIndexes)
        : _NarrowLayout(ctrl: ctrl, items: visibleItems, tabIndexes: visibleIndexes);
  }
}

// ── Wide Layout (Windows Sidebar) ─────────────────────────────────────────────
class _WideLayout extends StatelessWidget {
  final HomeController ctrl;
  final List<_NavItem> items;
  final List<int> tabIndexes;
  const _WideLayout({
    required this.ctrl,
    required this.items,
    required this.tabIndexes,
  });

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.to;
    final me = auth.user;
    return Scaffold(
      body: Row(children: [
        // ── Sidebar ───────────────────────────────────────────────────
        Container(
          width: 220,
          color: AppColors.primary,
          child: Column(children: [
            const SizedBox(height: 32),
            const Icon(Icons.local_hospital_rounded,
                color: Colors.white, size: 44),
            const SizedBox(height: 10),
            const Text('الصيدلة الإكلينيكية',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(me.name,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12)),
            if (me.isPharmacist)
              Obx(() => ctrl.deptName.value.isEmpty
                  ? const SizedBox.shrink()
                  : Text('قسم: ${ctrl.deptName.value}',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11))),
            if (me.isPharmacist)
              Obx(() => ctrl.pendingChangeText.value.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: Text(ctrl.pendingChangeText.value,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.amberAccent,
                              fontSize: 10)),
                    )),
            const SizedBox(height: 20),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 8),
            Expanded(
              // ⚠️ قيم الـ Rx لازم تتقرا هنا (جوه Obx مباشرة) مش جوه itemBuilder،
              // لأن itemBuilder بيشتغل بعد ما Obx يخلص فـ GetX كان بيطلّع خطأ
              // "improper use of GetX".
              child: Obx(() {
                final current = ctrl.currentIndex.value;
                final pending = ctrl.pendingRequests.value;
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) => _SidebarItem(
                    item: items[i],
                    selected: current == i,
                    badge: items[i].showsAdminBadge ? pending : 0,
                    onTap: () => ctrl.go(i),
                  ),
                );
              }),
            ),
            const Divider(color: Colors.white24, height: 1),
            if (me.isPharmacist)
              ListTile(
                leading: const Icon(Icons.swap_horiz_rounded,
                    color: Colors.white70, size: 20),
                title: const Text('تغيير القسم',
                    style: TextStyle(
                        fontFamily: 'Cairo', color: Colors.white70, fontSize: 13)),
                onTap: ctrl.changeDepartment,
              ),
            ListTile(
              leading: const Icon(Icons.lock_reset_rounded,
                  color: Colors.white70, size: 20),
              title: const Text('تغيير كلمة المرور',
                  style: TextStyle(
                      fontFamily: 'Cairo', color: Colors.white70, fontSize: 13)),
              onTap: showChangePasswordDialog,
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded,
                  color: Colors.white70, size: 20),
              title: const Text('تسجيل الخروج',
                  style: TextStyle(
                      fontFamily: 'Cairo', color: Colors.white70, fontSize: 13)),
              onTap: auth.logout,
            ),
            const SizedBox(height: 16),
          ]),
        ),
        // ── Content ───────────────────────────────────────────────────
        Expanded(
          child: Obx(() {
            final realIdx = tabIndexes[ctrl.currentIndex.value];
            return _allTabs[realIdx];
          }),
        ),
      ]),
    );
  }
}

// ── Narrow Layout (Android Bottom Nav) ────────────────────────────────────────
class _NarrowLayout extends StatelessWidget {
  final HomeController ctrl;
  final List<_NavItem> items;
  final List<int> tabIndexes;
  const _NarrowLayout({
    required this.ctrl,
    required this.items,
    required this.tabIndexes,
  });

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.to;
    final me = auth.user;
    return Obx(() {
      final visIdx = ctrl.currentIndex.value;
      final realIdx = tabIndexes[visIdx];
      return Scaffold(
        appBar: AppBar(
          title: Text(items[visIdx].label),
          actions: [
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'dept') ctrl.changeDepartment();
                if (v == 'pass') showChangePasswordDialog();
                if (v == 'logout') auth.logout();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(
                    me.isPharmacist && ctrl.deptName.value.isNotEmpty
                        ? '${me.name} — ${ctrl.deptName.value}'
                        : me.name,
                  ),
                ),
                if (me.isPharmacist)
                  const PopupMenuItem(value: 'dept', child: Text('تغيير القسم')),
                const PopupMenuItem(value: 'pass', child: Text('تغيير كلمة المرور')),
                const PopupMenuItem(value: 'logout', child: Text('تسجيل الخروج')),
              ],
            ),
          ],
        ),
        body: _allTabs[realIdx],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: visIdx,
          onTap: ctrl.go,
          items: items
              .map((i) => BottomNavigationBarItem(
                    icon: _navIcon(i, i.icon, ctrl.pendingRequests.value),
                    activeIcon:
                        _navIcon(i, i.activeIcon, ctrl.pendingRequests.value),
                    label: i.label,
                  ))
              .toList(),
        ),
      );
    });
  }

  Widget _navIcon(_NavItem i, IconData icon, int badge) =>
      (i.showsAdminBadge && badge > 0)
          ? Badge(label: Text('$badge'), child: Icon(icon))
          : Icon(icon);
}

// ── Sidebar Item ──────────────────────────────────────────────────────────────
class _SidebarItem extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Material(
          color: selected ? Colors.white.withOpacity(0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(children: [
                Icon(
                  selected ? item.activeIcon : item.icon,
                  color: selected ? Colors.white : Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item.label,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.normal,
                      )),
                ),
                if (badge > 0) Badge(label: Text('$badge')),
              ]),
            ),
          ),
        ),
      );
}
