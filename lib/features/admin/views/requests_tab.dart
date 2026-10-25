import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/org_models.dart';
import '../../../data/repositories/firebase_rest_service.dart';
import '../../../data/repositories/org_repository.dart';
import 'admin_screen.dart';

/// إشعارات المدير: طلبات تغيير القسم المعلّقة.
/// موافقة ← يتغير. رفض ← المدير يختار القسم. محدّش رد خلال 24 ساعة ← يتغير تلقائيًا.
class RequestsTab extends StatefulWidget {
  final AdminController ctrl;
  const RequestsTab({super.key, required this.ctrl});
  @override
  State<RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<RequestsTab> {
  final _repo = OrgRepository.instance;
  List<DeptRequest> _reqs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // بيطبّق كمان اللى عدّى مهلته
      final r = await _repo.pendingForHospital(widget.ctrl.hospitalId);
      await widget.ctrl.loadDepartments();
      widget.ctrl.pendingCount.value = r.length;
      if (mounted) setState(() => _reqs = r);
    } on ApiException catch (e) {
      Get.snackbar('خطأ', e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(DeptRequest r) async {
    try {
      await _repo.approve(r);
      await widget.ctrl.loadUsers();
    } on ApiException catch (e) {
      Get.snackbar('خطأ', e.message);
    }
    _load();
  }

  Future<void> _reject(DeptRequest r) async {
    final depts = widget.ctrl.departments.toList();
    String? chosen;
    final ok = await Get.dialog<bool>(AlertDialog(
      title: Text('رفض طلب ${r.userName} — اختر له القسم',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 15)),
      content: StatefulBuilder(
        builder: (_, set) => DropdownButton<String>(
          isExpanded: true,
          value: chosen,
          hint: const Text('القسم'),
          items: depts
              .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
              .toList(),
          onChanged: (v) => set(() => chosen = v),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('إلغاء')),
        ElevatedButton(
            onPressed: () => Get.back(result: true),
            child: const Text('تأكيد')),
      ],
    ));
    if (ok != true || chosen == null) return;
    try {
      await _repo.rejectAndAssign(r, chosen!);
      await widget.ctrl.loadUsers();
    } on ApiException catch (e) {
      Get.snackbar('خطأ', e.message);
    }
    _load();
  }

  String _hoursLeft(DeptRequest r) {
    final left = r.autoApproveAt.difference(DateTime.now());
    if (left.inMinutes <= 0) return 'أقل من دقيقة';
    if (left.inHours >= 1) return '${left.inHours} ساعة';
    return '${left.inMinutes} دقيقة';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _reqs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: _reqs.isEmpty
          ? ListView(children: const [
              SizedBox(height: 120),
              Center(
                  child: Text('لا توجد طلبات معلّقة',
                      style: TextStyle(
                          fontFamily: 'Cairo', color: AppColors.textSecond))),
            ])
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _reqs
                  .map((r) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${r.userName} عايز يغيّر قسمه',
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                              const SizedBox(height: 4),
                              Obx(() => Text(
                                  'من ${widget.ctrl.deptName(r.fromDeptId)}  ←  إلى ${widget.ctrl.deptName(r.toDeptId)}',
                                  style: const TextStyle(
                                      fontFamily: 'Cairo', fontSize: 13))),
                              const SizedBox(height: 4),
                              Text(
                                  'لو محدّش رد، يتطبق تلقائيًا بعد ${_hoursLeft(r)}',
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: AppColors.textSecond)),
                              const SizedBox(height: 8),
                              Row(children: [
                                TextButton(
                                    onPressed: () => _reject(r),
                                    child: const Text('رفض',
                                        style: TextStyle(
                                            color: AppColors.danger))),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                    onPressed: () => _approve(r),
                                    child: const Text('موافقة')),
                              ]),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
    );
  }
}
