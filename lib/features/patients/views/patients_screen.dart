import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/patient_model.dart';
import '../controllers/patients_controller.dart';

class PatientsScreen extends StatelessWidget {
  const PatientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // الـ controller متسجل permanent في HomeController
    final ctrl = Get.find<PatientsController>();

    return Column(
      children: [
        _SearchBar(ctrl: ctrl),
        _StatusFilter(ctrl: ctrl),
        Expanded(child: _PatientList(ctrl: ctrl)),
      ],
    );
  }
}

// ── Search Bar ───────────────────────────────────────────────────────────────
class _SearchBar extends StatefulWidget {
  final PatientsController ctrl;
  const _SearchBar({required this.ctrl});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _tc = TextEditingController();

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: TextField(
          controller: _tc,
          onChanged: widget.ctrl.setSearch,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            hintText: 'ابحث بالاسم أو رقم الملف...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: Obx(() => widget.ctrl.searchQuery.value.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _tc.clear();
                      widget.ctrl.setSearch('');
                    },
                  )),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          ),
        ),
      );
}

// ── Status Filter ─────────────────────────────────────────────────────────────
class _StatusFilter extends StatelessWidget {
  final PatientsController ctrl;
  const _StatusFilter({required this.ctrl});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _FilterChip(label: 'الكل', value: 'all', ctrl: ctrl),
            const SizedBox(width: 8),
            _FilterChip(label: '🟢 نشط', value: 'active', ctrl: ctrl),
            const SizedBox(width: 8),
            _FilterChip(label: '⚪ خرج', value: 'discharged', ctrl: ctrl),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'تحديث',
              color: AppColors.primary,
              onPressed: () => ctrl.load(force: true),
            ),
            Obx(() => Text(
                  '${ctrl.filteredPatients.length} مريض',
                  style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: AppColors.textSecond),
                )),
          ],
        ),
      );
}

class _FilterChip extends StatelessWidget {
  final String label, value;
  final PatientsController ctrl;
  const _FilterChip(
      {required this.label, required this.value, required this.ctrl});

  @override
  Widget build(BuildContext context) => Obx(() {
        final selected = ctrl.statusFilter.value == value;
        return GestureDetector(
          onTap: () => ctrl.setStatusFilter(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppColors.primary : Colors.grey.shade300,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? Colors.white : AppColors.textSecond,
              ),
            ),
          ),
        );
      });
}

// ── Patient List ──────────────────────────────────────────────────────────────
class _PatientList extends StatelessWidget {
  final PatientsController ctrl;
  const _PatientList({required this.ctrl});

  @override
  Widget build(BuildContext context) => Obx(() {
        if (ctrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (ctrl.loadError.value.isNotEmpty && ctrl.allPatients.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded,
                      size: 56, color: AppColors.danger),
                  const SizedBox(height: 12),
                  const Text('تعذّر تحميل المرضى',
                      style: TextStyle(
                          fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(ctrl.loadError.value,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecond)),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () => ctrl.load(force: true),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }
        if (ctrl.filteredPatients.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline_rounded,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  ctrl.searchQuery.value.isNotEmpty
                      ? 'لا توجد نتائج للبحث'
                      : 'لا يوجد مرضى بعد',
                  style: const TextStyle(
                      fontFamily: 'Cairo', color: AppColors.textSecond),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => ctrl.load(force: true),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: ctrl.filteredPatients.length,
            itemBuilder: (_, i) =>
                PatientCard(patient: ctrl.filteredPatients[i]),
          ),
        );
      });
}

// ── Patient Card ──────────────────────────────────────────────────────────────
class PatientCard extends StatelessWidget {
  final PatientModel patient;
  const PatientCard({super.key, required this.patient});

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Get.toNamed('/patient/${patient.id}');
            // رجوع من ملف المريض → حدّث (لو خرّجته بيتجاوز الفاصل الزمني)
            PatientsController.to.load();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        patient.name,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    _StatusBadge(status: patient.status),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    _InfoChip(Icons.person_outline_rounded,
                        'عمر ${patient.ageText}'),
                    if (patient.weightKg != null)
                      _InfoChip(Icons.monitor_weight_outlined,
                          '${patient.weightKg!.toStringAsFixed(0)} kg'),
                    _InfoChip(
                        Icons.folder_outlined, 'ملف: ${patient.fileNumber}'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        patient.diagnosisText,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          color: AppColors.textSecond,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 12, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(
                          patient.displayAdmission,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (patient.prescribedMedications.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.medication_outlined,
                          size: 13, color: AppColors.primary.withOpacity(0.7)),
                      const SizedBox(width: 4),
                      Text(
                        '${patient.prescribedMedications.length} أدوية',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: AppColors.primary.withOpacity(0.8),
                        ),
                      ),
                      if (patient.hasAllergies) ...[
                        const SizedBox(width: 12),
                        const Icon(Icons.warning_amber_rounded,
                            size: 13, color: AppColors.warning),
                        const SizedBox(width: 4),
                        const Text('حساسية',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11,
                                color: AppColors.warning)),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.success.withOpacity(0.12)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.success.withOpacity(0.4)
              : Colors.grey.shade300,
        ),
      ),
      child: Text(
        isActive ? '🟢 نشط' : '⚪ خرج',
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isActive ? AppColors.success : Colors.grey.shade500,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecond),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  color: AppColors.textSecond)),
        ],
      );
}
