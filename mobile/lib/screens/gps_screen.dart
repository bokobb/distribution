import 'package:flutter/material.dart';

import '../location.dart';
import '../theme.dart';

/// Один раз после входа: разрешить местоположение. Тогда рабочий день начинается сам, когда сотрудник открывает
/// приложение в рабочее время, — «Начать рабочий день» нажимать не нужно. «Позже» — день начинают кнопкой.
class GpsScreen extends StatefulWidget {
  const GpsScreen({super.key, required this.location, required this.onDone});

  final LocationSource location;
  final VoidCallback onDone;

  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> {
  bool _busy = false;
  String? _problem;

  Future<void> _allow() async {
    setState(() => _busy = true);
    final problem = await widget.location.ensureAccess();
    if (!mounted) return;
    if (problem == null) return widget.onDone();
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                    child: const Icon(Icons.location_on_outlined, size: 52, color: AppColors.accent),
                  ),
                ),
                const SizedBox(height: 24),
                const Text('Местоположение',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, height: 34 / 28, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                const Text(
                    'Разрешите доступ — и рабочий день будет начинаться сам, когда вы открываете приложение '
                    'в рабочее время. Нажимать «Начать рабочий день» не нужно.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, height: 22 / 15, color: AppColors.text2)),
                const SizedBox(height: 8),
                const Text('Путь и визиты отмечаются только в рабочий день; в конце рабочего времени он закрывается сам.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, height: 20 / 14, color: AppColors.text2)),
                if (_problem != null) ...[
                  const SizedBox(height: 16),
                  Text(_problem!,
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.err)),
                ],
                const Spacer(flex: 3),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: _busy ? null : _allow,
                  child: const Text('Разрешить'),
                ),
                const SizedBox(height: 4),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: AppColors.text2),
                  onPressed: _busy ? null : widget.onDone,
                  child: const Text('Позже'),
                ),
              ],
            ),
          ),
        ),
      );
}
