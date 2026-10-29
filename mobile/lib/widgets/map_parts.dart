import 'package:flutter/material.dart';

import '../theme.dart';

/// Тень кнопок и плашек поверх карты.
const mapShadow = [BoxShadow(color: Color(0x29101318), blurRadius: 10, offset: Offset(0, 2))];

/// Где торговый: точка с ореолом.
class MapMe extends StatelessWidget {
  const MapMe({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Вы здесь',
        child: Container(
          decoration: const BoxDecoration(color: Color(0x3D4136F1), shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Container(
            width: 17,
            height: 17,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x4D101318), blurRadius: 4, offset: Offset(0, 1))],
            ),
          ),
        ),
      );
}

/// Круглая белая кнопка поверх карты: «Назад», «Показать меня».
class MapRound extends StatelessWidget {
  const MapRound({super.key, required this.tooltip, required this.icon, required this.onTap, this.busy = false});

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: mapShadow),
        child: IconButton(
          tooltip: tooltip,
          onPressed: busy ? null : onTap,
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, size: 22, color: AppColors.text),
        ),
      );
}
