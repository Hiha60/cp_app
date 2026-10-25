import 'package:get/get.dart';
import '../../../data/models/patient_model.dart';
import '../../../data/repositories/patient_repository.dart';
import '../../auth/controllers/auth_controller.dart';

class PatientsController extends GetxController {
  static PatientsController get to => Get.find();

  final _repo = PatientRepository.instance;

  final allPatients      = <PatientModel>[].obs;
  final filteredPatients = <PatientModel>[].obs;
  final isLoading        = true.obs;
  final loadError        = ''.obs;
  final searchQuery      = ''.obs;
  final statusFilter     = 'all'.obs;

  // ── تحميل عند الطلب بس (مفيش polling) ────────────────────────────────
  // أقل فاصل بين تحميلين تلقائيين — بيمنع تحميلات متكررة لو قلبت بين التابات
  static const _minGap = Duration(seconds: 15);
  DateTime? _lastLoad;
  bool _loading = false;
  bool _dirty = false;

  @override
  void onInit() {
    super.onInit();
    ever(allPatients,  (_) => _applyFilter());
    ever(searchQuery,  (_) => _applyFilter());
    ever(statusFilter, (_) => _applyFilter());
    load(force: true);
  }

  /// علّم إن البيانات اتغيّرت (خروج مريض/إضافة) — التحميل الجاي هيتجاوز الفاصل
  void markDirty() => _dirty = true;

  /// يجيب مرضى المستشفى مرة واحدة.
  ///  force: يتجاوز الفاصل الزمني (زر التحديث، أول تحميل)
  Future<void> load({bool force = false}) async {
    if (_loading) return;
    final last = _lastLoad;
    if (!force &&
        !_dirty &&
        last != null &&
        DateTime.now().difference(last) < _minGap) {
      return;
    }
    _loading = true;
    // السبينر الكبير بس لو مفيش بيانات معروضة — غير كده نحدّث من ورا القايمة
    if (allPatients.isEmpty) isLoading.value = true;
    try {
      final hospitalId = AuthController.to.user.hospitalId;
      if (hospitalId.isEmpty) {
        // السوبر أدمن مالوش مستشفى → مفيش مرضى يتجابوا (القواعد هترفض الاستعلام)
        allPatients.clear();
        loadError.value = '';
        return;
      }
      allPatients.value = await _repo.fetchPatients(hospitalId: hospitalId);
      _lastLoad = DateTime.now();
      _dirty = false;
      loadError.value = '';
    } catch (e) {
      loadError.value = '$e';
    } finally {
      _loading = false;
      isLoading.value = false;
    }
  }

  void _applyFilter() {
    var list = allPatients.toList();
    if (statusFilter.value != 'all') {
      list = list.where((p) => p.status == statusFilter.value).toList();
    }
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.fileNumber.contains(q)
      ).toList();
    }
    filteredPatients.value = list;
  }

  void setSearch(String v)       => searchQuery.value  = v;
  void setStatusFilter(String v) => statusFilter.value = v;

  Future<void> dischargePatient(String id) async {
    await _repo.discharge(id);
  }

  int get totalActive     => allPatients.where((p) => p.isActive).length;
  int get totalDischarged => allPatients.where((p) => p.isDischarged).length;
  int get totalToday {
    final today = DateTime.now();
    return allPatients.where((p) =>
      p.admissionDate.year  == today.year  &&
      p.admissionDate.month == today.month &&
      p.admissionDate.day   == today.day
    ).length;
  }
}
