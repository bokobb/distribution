import 'package:flutter/material.dart';

import '../theme.dart';

/// Плашка с текстом: ошибка — малиновая, подсказка — на пергаменте.
class MessageBox extends StatelessWidget {
  const MessageBox.error(this.text, {super.key}) : error = true;

  const MessageBox.info(this.text, {super.key}) : error = false;

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: error ? AppColors.crimsonSoft : AppColors.paperDeep,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Text(text, style: TextStyle(color: error ? AppColors.crimson : AppColors.ink)),
      );
}
