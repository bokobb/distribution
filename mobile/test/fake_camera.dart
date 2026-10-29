import 'dart:io';

import 'package:distribution_mobile/camera.dart';

/// Камера для тестов: «снимок» — маленький JPEG во временной папке.
class FakeCamera implements PhotoSource {
  FakeCamera() : dir = Directory.systemTemp.createTempSync('photos');

  final Directory dir;

  /// Человек закрыл камеру, не сняв.
  bool cancel = false;
  int _n = 0;

  static const jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];

  @override
  Future<String?> photo(String id) async {
    if (cancel) return null;
    final f = File('${dir.path}/$id-${++_n}.jpg');
    await f.writeAsBytes(jpeg);
    return f.path;
  }

  @override
  Future<String> keep(String name, List<int> bytes) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  @override
  Future<void> clear() async {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
