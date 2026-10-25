import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/org_models.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/firebase_rest_service.dart';
import '../../../data/repositories/org_repository.dart';
import '../../auth/controllers/auth_controller.dart';

/// Super Admin فقط: إضافة مستشفى جديدة + مدير ليها.
/// (القواعد فى firestore.rules بترفض أى حد غير السوبر أدمن حتى لو عدّى الواجهة)
class HospitalsTab extends StatefulWidget {
  const HospitalsTab({super.key});
  @override
  State<HospitalsTab> createState() => _HospitalsTabState();
}

class _HospitalsTabState extends State<HospitalsTab> {
  final _formKey = GlobalKey<FormState>();
  final _hospital = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _pass = TextEditingController();
  bool _saving = false;
  bool _showPass = false;
  List<HospitalModel> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_hospital, _name, _code, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await OrgRepository.instance.listHospitals();
      if (mounted) setState(() => _list = l);
    } on ApiException catch (e) {
      Get.snackbar('خطأ', e.message);
    }
  }

  Future<void> _create() async {
    if (!AuthController.to.user.isSuperAdmin) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await OrgRepository.instance.createHospitalWithAdmin(
        hospitalName: _hospital.text,
        adminName: _name.text,
        adminCode: _code.text,
        adminPassword: _pass.text,
      );
      Get.snackbar('✅ تم', 'تم إنشاء المستشفى والمدير',
          backgroundColor: AppColors.success,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM);
      for (final c in [_hospital, _name, _code, _pass]) {
        c.clear();
      }
      await _load();
    } on AuthException catch (e) {
      Get.snackbar('خطأ', e.message,
          backgroundColor: AppColors.danger, colorText: Colors.white);
    } on ApiException catch (e) {
      Get.snackbar('خطأ', e.message,
          backgroundColor: AppColors.danger, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('مستشفى جديدة',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Form(
              key: _formKey,
              child: Column(children: [
                TextFormField(
                  controller: _hospital,
                  textDirection: TextDirection.rtl,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'أدخل اسم المستشفى' : null,
                  decoration: const InputDecoration(
                      labelText: 'اسم المستشفى',
                      prefixIcon: Icon(Icons.local_hospital_outlined)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  textDirection: TextDirection.rtl,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'أدخل اسم المدير' : null,
                  decoration: const InputDecoration(
                      labelText: 'اسم المدير (للدخول)',
                      prefixIcon: Icon(Icons.person_outline_rounded)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => RegExp(r'^\d{4}$').hasMatch((v ?? '').trim())
                      ? null
                      : '4 أرقام فقط',
                  decoration: const InputDecoration(
                      labelText: 'الرقم التعريفي للمدير',
                      counterText: '',
                      prefixIcon: Icon(Icons.tag_rounded)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pass,
                  obscureText: !_showPass,
                  textDirection: TextDirection.ltr,
                  validator: AuthController.validateNewPassword,
                  decoration: InputDecoration(
                    labelText: 'كلمة مرور المدير',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_showPass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _create,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.add_business_rounded),
                    label: Text(_saving ? 'جاري الإنشاء...' : 'إنشاء المستشفى'),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            const Text('المستشفيات',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ..._list.map((h) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_hospital_rounded,
                        color: AppColors.primary),
                    title: Text(h.name,
                        style: const TextStyle(
                            fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
                  ),
                )),
          ],
        ),
      );
}
