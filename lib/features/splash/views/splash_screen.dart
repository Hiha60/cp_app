import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/local_db_service.dart';
import '../../auth/controllers/auth_controller.dart';

class SplashController extends GetxController {
  final progress = Rxn<double>(); // null = شريط غير محدد
  final status = 'جاري التحضير...'.obs;
  final error = ''.obs;

  @override
  void onReady() {
    super.onReady();
    start();
  }

  Future<void> start() async {
    error.value = '';
    progress.value = null;
    status.value = 'جاري التحضير...';

    LocalDbService.instance.onProgress = (p, s) {
      progress.value = p;
      status.value = s;
    };

    try {
      await LocalDbService.instance.init();

      if (!Get.isRegistered<AuthController>()) {
        Get.put(AuthController(), permanent: true);
      }
      final loggedIn = await AuthController.to.restoreSession();
      Get.offAllNamed(loggedIn ? '/home' : '/login');
    } on SocketException {
      error.value = 'تعذّر الاتصال بالإنترنت.\nتأكد من الشبكة وحاول مرة أخرى.';
    } on HttpException {
      error.value = 'تعذّر الوصول لسيرفر التحميل.';
    } catch (e) {
      error.value = 'حدث خطأ أثناء تجهيز قاعدة البيانات:\n$e';
    } finally {
      LocalDbService.instance.onProgress = null;
    }
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(SplashController());

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withOpacity(0.3), width: 2),
                    ),
                    child: const Icon(Icons.local_hospital_rounded,
                        size: 52, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'الصيدلة الإكلينيكية',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Obx(() => ctrl.error.isNotEmpty
                      ? _ErrorView(ctrl: ctrl)
                      : _ProgressView(ctrl: ctrl)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressView extends StatelessWidget {
  final SplashController ctrl;
  const _ProgressView({required this.ctrl});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ctrl.progress.value,
              minHeight: 8,
              backgroundColor: Colors.white24,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            ctrl.status.value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              color: Colors.white.withOpacity(0.85),
            ),
          ),
        ],
      );
}

class _ErrorView extends StatelessWidget {
  final SplashController ctrl;
  const _ErrorView({required this.ctrl});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          Text(
            ctrl.error.value,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: 'Cairo', fontSize: 13, color: Colors.white),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: ctrl.start,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
            ),
          ),
        ],
      );
}
