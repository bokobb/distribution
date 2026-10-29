import 'package:flutter/material.dart';

import '../theme.dart';

/// Плашка с текстом: ошибка — красная, внимание (нет сети, ждёт отправки) — янтарная, «всё хорошо» — зелёная,
/// подсказка — серая. title — первые слова жирным («Нет сети.»); onTap — плашку можно нажать.
class MessageBox extends StatelessWidget {
  const MessageBox.error(this.text, {super.key, this.title, this.onTap}) : _kind = _Kind.error;

  const MessageBox.info(this.text, {super.key, this.title, this.onTap}) : _kind = _Kind.info;

  const MessageBox.warn(this.text, {super.key, this.title, this.onTap}) : _kind = _Kind.warn;

  const MessageBox.ok(this.text, {super.key, this.title, this.onTap}) : _kind = _Kind.ok;

  final String text;
  final String? title;
  final VoidCallback? onTap;
  final _Kind _kind;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (_kind) {
      _Kind.error => (AppColors.errBg, const Color(0xFFA3241A), Icons.error_outline),
      _Kind.warn => (AppColors.warnBg, const Color(0xFF6E4100), Icons.cloud_off_outlined),
      _Kind.ok => (AppColors.okBg, const Color(0xFF0B5A40), Icons.check_circle_outline),
      _Kind.info => (AppColors.fill, AppColors.text, Icons.info_outline),
    };
    return Material(
      color: bg,
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    if (title != null) TextSpan(text: '$title ', style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: text),
                  ]),
                  style: TextStyle(fontSize: 14, height: 20 / 14, color: fg),
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, size: 20, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Kind { error, info, warn, ok }
