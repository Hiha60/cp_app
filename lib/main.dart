import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

import 'core/theme/app_theme.dart';
import 'features/splash/views/splash_screen.dart';
import 'features/auth/views/login_screen.dart';
import 'features/home/views/home_screen.dart';
import 'features/patients/views/patient_file_screen.dart';
import 'features/update/update_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // ❌ اتشالوا: LocalDbService.instance.init() و Get.put(AuthController)
  // الـ splash بيعملهم بعد ما يظهر الـ UI

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const ClinicalPharmacyApp());
}

class ClinicalPharmacyApp extends StatelessWidget {
  const ClinicalPharmacyApp({super.key});

  @override
  Widget build(BuildContext context) => GetMaterialApp(
        title: 'الصيدلة الإكلينيكية',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        // ⚠️ لازم عشان أي حاجة بتحتاج MaterialLocalizations زي showDatePicker —
        // من غيرها بيرمي "No MaterialLocalizations found" فورًا. محتاج كمان
        // إضافة flutter_localizations كـ dependency في pubspec.yaml.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ar'),
          Locale('en'),
        ],
        textDirection: TextDirection.rtl,
        // 👈 جديد: UpdateGate بتلف التطبيق كله وبتفرض التحديث الإجباري
        builder: (ctx, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: UpdateGate(child: child!),
        ),
        theme: AppTheme.light,
        initialRoute: '/splash',
        getPages: [
          GetPage(name: '/splash', page: () => const SplashScreen()),
          GetPage(name: '/login', page: () => const LoginScreen()),
          GetPage(name: '/home', page: () => const HomeScreen()),
          GetPage(
            name: '/patient/:id',
            page: () => PatientFileScreen(patientId: Get.parameters['id']!),
          ),
        ],
        unknownRoute: GetPage(
          name: '/notfound',
          page: () => const Scaffold(
            body: Center(child: Text('الصفحة غير موجودة')),
          ),
        ),
      );
}
