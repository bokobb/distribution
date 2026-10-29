import 'dart:io';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../visits.dart';

/// «Сфотографировать полку» к идущему визиту — пунктирная плитка, как в макете AgentNoOrder; снято — миниатюра и
/// «Переснять». [required] — фото обязательно по настройкам компании.
class ShelfPhotoButton extends StatefulWidget {
  const ShelfPhotoButton({super.key, required this.visits, required this.required});

  final VisitBook visits;
  final bool required;

  @override
  State<ShelfPhotoButton> createState() => _ShelfPhotoButtonState();
}

class _ShelfPhotoButtonState extends State<ShelfPhotoButton> {
  bool _busy = false;

  Future<void> _take() async {
    setState(() => _busy = true);
    try {
      final problem = await widget.visits.takePhoto();
      if (problem != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.visits,
        builder: (context, _) {
          final photo = widget.visits.current?.photo;
          return Material(
            color: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              side: BorderSide(color: photo == null ? const Color(0xFFC9CDD5) : AppColors.line, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _busy ? null : _take,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: photo == null ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    if (photo == null)
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                            color: AppColors.fill, borderRadius: BorderRadius.all(Radius.circular(12))),
                        child: _busy
                            ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.photo_camera_outlined, color: AppColors.text),
                      )
                    else
                      ClipRRect(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        child: Image.file(File(photo),
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                                width: 56, height: 56, child: Icon(Icons.broken_image_outlined, color: AppColors.icon))),
                      ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(photo == null ? 'Сфотографировать полку' : 'Фото полки снято',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          if (photo != null)
                            const Text('Нажмите, чтобы переснять', style: TextStyle(fontSize: 13, color: AppColors.text2))
                          else if (widget.required)
                            const Text('Обязательно для этого магазина',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF8A5000))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
