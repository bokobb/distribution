import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Фото полки: камера телефона и папка с фото до отправки — отдельно от визитов, чтобы проверять их без камеры.
abstract class PhotoSource {
  /// Снять фото полки для визита; вернуть путь к новому файлу на телефоне. Отменили съёмку — null.
  Future<String?> shelf(String visitUuid);

  /// Стереть все фото — при выходе.
  Future<void> clear();
}

/// Камера (image_picker): JPEG не больше 1600 px — несколько сотен КБ, уходит и по слабой сети.
class DeviceCamera implements PhotoSource {
  final _picker = ImagePicker();

  static Future<Directory> _dir() async => Directory(p.join((await getApplicationDocumentsDirectory()).path, 'photos'));

  @override
  Future<String?> shelf(String visitUuid) async {
    final shot = await _picker.pickImage(
        source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 75);
    if (shot == null) return null;
    final dir = await _dir();
    await dir.create(recursive: true);
    // новое имя на каждый снимок: переснятое фото не покажется старым из кеша картинок
    final path = p.join(dir.path, '$visitUuid-${DateTime.now().millisecondsSinceEpoch}.jpg');
    await File(shot.path).copy(path);
    try {
      await File(shot.path).delete();
    } on FileSystemException {
      // временный файл камеры — сотрёт система
    }
    return path;
  }

  @override
  Future<void> clear() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
