import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/update_service.dart';

/// شاشة التحديث الإجباري — مفيش منها رجوع، الطريق الوحيد زر التحميل.
class UpdateRequiredScreen extends StatelessWidget {
  final UpdateStatus status;
  final VoidCallback? onRetry;
  const UpdateRequiredScreen({super.key, required this.status, this.onRetry});

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: AppColors.primary,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.system_update_rounded,
                        size: 80, color: Colors.white),
                    const SizedBox(height: 20),
                    const Text(
                      'تحديث مطلوب',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      status.message ?? 'يجب تحديث البرنامج للمتابعة',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Cairo', color: Colors.white70),
                    ),
                    if (status.latest != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'أحدث إصدار: ${status.latest}',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.white60),
                      ),
                    ],
                    const SizedBox(height: 28),
                    if (status.url != null)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primary,
                        ),
                        onPressed: () => launchUrl(
                          Uri.parse(status.url!),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('تحميل التحديث'),
                      ),
                    if (onRetry != null) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: onRetry,
                        child: const Text('أعدت التحديث؟ تحقق مرة أخرى',
                            style: TextStyle(
                                fontFamily: 'Cairo', color: Colors.white70)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
