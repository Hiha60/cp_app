import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/repositories/firebase_rest_service.dart';
import '../../../data/repositories/org_repository.dart';
import 'admin_screen.dart';

/// أقسام المستشفى — المدير يضيف ويعرض.
class DepartmentsTab extends StatefulWidget {
  final AdminController ctrl;
  const DepartmentsTab({super.key, required this.ctrl});
  @override
  State<DepartmentsTab> createState() => _DepartmentsTabState();
}

class _DepartmentsTabState extends State<DepartmentsTab> {
  final _c = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _c.text.trim();
    if (name.isEmpty) return;
    if (widget.ctrl.departments.any((d) => d.name.toLowerCase() == name.toLowerCase())) {
      Get.snackbar('تنبيه', 'القسم موجود بالفعل');
      return;
    }
    setState(() => _saving = true);
    try {
      await OrgRepository.instance.addDepartment(widget.ctrl.hospitalId, name);
      _c.clear();
      await widget.ctrl.loadDepartments();
    } on ApiException catch (e) {
      Get.snackbar('خطأ', e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: widget.ctrl.loadDepartments,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  textDirection: TextDirection.rtl,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    hintText: 'اسم القسم (مثال: العناية المركزة)',
                    prefixIcon: Icon(Icons.apartment_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _saving ? null : _add,
                child: const Text('إضافة'),
              ),
            ]),
            const SizedBox(height: 12),
            Obx(() {
              final list = widget.ctrl.departments;
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: Text('لا توجد أقسام بعد',
                        style: TextStyle(
                            fontFamily: 'Cairo', color: AppColors.textSecond)),
                  ),
                );
              }
              return Column(
                children: list
                    .map((d) => Card(
                          child: ListTile(
                            leading: const Icon(Icons.apartment_rounded,
                                color: AppColors.primary),
                            title: Text(d.name,
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w600)),
                          ),
                        ))
                    .toList(),
              );
            }),
          ],
        ),
      );
}
