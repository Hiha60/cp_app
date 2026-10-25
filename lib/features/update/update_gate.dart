import 'package:flutter/material.dart';
import '../../core/services/update_service.dart';
import 'update_required_screen.dart';

/// بوابة التحديث: بتلف التطبيق كله (من الـ builder في GetMaterialApp).
/// - بتفحص في الخلفية أول ما التطبيق يفتح، فالـ splash مش بيتأخر.
/// - لو الإصدار أقدم من min_version بتستبدل التطبيق كله بشاشة التحديث.
/// - بتعيد الفحص كل ما التطبيق يرجع من الخلفية (resumed).
class UpdateGate extends StatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  UpdateStatus? _blocked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final s = await UpdateService.instance.check();
    if (!mounted) return;
    setState(() => _blocked = s.mustUpdate ? s : null);
  }

  @override
  Widget build(BuildContext context) {
    final b = _blocked;
    if (b != null) {
      return UpdateRequiredScreen(status: b, onRetry: _check);
    }
    return widget.child;
  }
}
