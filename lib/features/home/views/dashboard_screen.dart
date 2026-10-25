import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:cp_app/core/constants/app_constants.dart';
import 'package:cp_app/features/auth/controllers/auth_controller.dart';
import 'package:cp_app/features/patients/controllers/patients_controller.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.to;
    final patients = Get.find<PatientsController>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Greeting ──────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryDark],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Colors.white24,
                radius: 24,
                child: Icon(Icons.local_hospital_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Obx(() => Text(
                          'مرحباً، ${auth.user.name} 👋',
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700),
                        )),
                    const SizedBox(height: 2),
                    Text(
                      _greeting(),
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Quick Stats ───────────────────────────────────────────────
        const Text('إحصائيات سريعة',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 10),

        Obx(() => GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _QuickCard(
                  label: 'مرضى نشطون',
                  value: '${patients.totalActive}',
                  icon: Icons.people_rounded,
                  color: AppColors.primary,
                ),
                _QuickCard(
                  label: 'دخول اليوم',
                  value: '${patients.totalToday}',
                  icon: Icons.today_rounded,
                  color: AppColors.success,
                ),
                _QuickCard(
                  label: 'خرجوا',
                  value: '${patients.totalDischarged}',
                  icon: Icons.logout_rounded,
                  color: AppColors.textSecond,
                ),
                _QuickCard(
                  label: 'الإجمالي',
                  value: '${patients.allPatients.length}',
                  icon: Icons.folder_outlined,
                  color: AppColors.info,
                ),
              ],
            )),
        const SizedBox(height: 20),

        // ── Recent Patients ────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('آخر المرضى',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            TextButton(
              onPressed: () {},
              child: const Text('عرض الكل',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),

        Obx(() {
          final recent = patients.allPatients.take(5).toList();
          if (recent.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا يوجد مرضى بعد',
                    style: TextStyle(
                        fontFamily: 'Cairo', color: AppColors.textSecond)),
              ),
            );
          }
          return Column(
            children: recent
                .map((p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: p.isActive
                            ? AppColors.primary.withOpacity(0.1)
                            : Colors.grey.shade100,
                        child: Icon(Icons.person_rounded,
                            color: p.isActive
                                ? AppColors.primary
                                : Colors.grey.shade400,
                            size: 20),
                      ),
                      title: Text(p.name,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      subtitle: Text(
                        '${p.diagnosisText}  •  ${p.displayAdmission}',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: AppColors.textSecond),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: p.isActive
                              ? AppColors.success.withOpacity(0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          p.isActive ? '🟢 نشط' : '⚪ خرج',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: p.isActive
                                ? AppColors.success
                                : Colors.grey.shade500,
                          ),
                        ),
                      ),
                      onTap: () => Get.toNamed('/patient/${p.id}'),
                    ))
                .toList(),
          );
        }),
      ],
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'صباح الخير — الصيدلة الإكلينيكية';
    if (h < 18) return 'مساء الخير — الصيدلة الإكلينيكية';
    return 'مساء النور — الصيدلة الإكلينيكية';
  }
}

class _QuickCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _QuickCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
            ]),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: color)),
                Text(label,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: AppColors.textSecond)),
              ],
            ),
          ],
        ),
      );
}
