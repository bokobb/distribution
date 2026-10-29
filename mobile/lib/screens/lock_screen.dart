import 'package:flutter/material.dart';

import '../app_lock.dart';
import '../theme.dart';

/// Замок поверх приложения: «Войти по отпечатку» — системное окно открывается само; не узнало — можно ввести
/// PIN-код телефона в том же окне или нажать ещё раз. Под замком приложение живёт: GPS и отправка идут.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock, required this.name});

  final AppLock lock;

  /// Кто вошёл — «Ержан Т.».
  final String name;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    final ok = await widget.lock.unlock();
    if (mounted && !ok) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.lock.label ?? 'отпечаток';
    final face = label == 'лицо';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
                  child: Icon(face ? Icons.face_outlined : Icons.fingerprint, size: 56, color: AppColors.accent),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Дистрибуция',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 28, height: 34 / 28, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(widget.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: AppColors.text2)),
              if (_failed) ...[
                const SizedBox(height: 16),
                const Text('Не получилось. Нажмите ещё раз — в окне телефона можно ввести и PIN-код телефона.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.err)),
              ],
              const Spacer(flex: 3),
              ListenableBuilder(
                listenable: widget.lock,
                builder: (context, _) => FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: widget.lock.checking ? null : _unlock,
                  icon: Icon(face ? Icons.face_outlined : Icons.fingerprint),
                  label: Text('Войти ${widget.lock.by}'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
